#
# Copyright (c) 2012 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'tmpdir'
require 'openssl'
require 'base64'

require 'net/http'
require 'uri'
require 'rexml/document'
require 'socket'
require 'net-dhcp'
require 'timeout'

class NoOption245Error < Exception; end

module RightScale

  module MetadataSources

    # Azure doesn't really have any sort of unified metadata service. It currently has three separate sources to stitch together for userdata and metadata:
    #   1. A cdrom drive is mounted at startup by the WALinuxAgent service. This has an xml file with Hostname, Username/password info, UserData (called CustomData). The CustomData is a newer thing which we don't use unfortunately, as it would be handy
    #   2. Certificate metadata source. Currently used ONLY for userdata. This is a proprietary "hacky" solution in which we stuff secret userdata in a X509 certificate attached to the instance at Launch time
    #   3. Azure has a metadata service with HostName, Networking information, Instance information, Plugin information, and some other goodies in its "fabric controller". This is XML served via a web service. The url of that web service is passed as "option 245" in the DHCP server response at bootup
    #   We currently use 2 for userdata and 3 for metadata above, though we'd like to use 1 for userdata and 3 for metadata and ditch our solution
    class AzureMetadataSource < MetadataSource
      class SharedConfig
        REQUIRED_ELEMENTS = ["*/Deployment", "*/*/Service", "*/*/ServiceInstance", "*/Incarnation", "*/Role" ]

        class InvalidConfig < StandardError; end

        def initialize(shared_config_content)
          @shared_config = REXML::Document.new shared_config_content
          raise InvalidConfig unless @shared_config.root.name == "SharedConfig"
          raise InvalidConfig unless REQUIRED_ELEMENTS.all? { |element| @shared_config.elements[element] }
        end

        def service_name
          @service_name ||= @shared_config.elements["SharedConfig/Deployment/Service"].attributes["name"] rescue nil
        end

        def instance_id
          @instance_id ||= @shared_config.elements["SharedConfig/Instances/Instance"].attributes["id"] rescue nil
        end

        def private_ip
          @private_ip ||= @shared_config.elements["SharedConfig/Instances/Instance"].attributes["address"] rescue nil
        end

        def inputs_endpoints
          @inputs_endpoints ||= [].tap do |endpoints|
            endpoint = @shared_config.elements["SharedConfig/Instances/Instance/InputEndpoints/Endpoint"] rescue nil
            while endpoint
              endpoints << endpoint
              endpoint = endpoint.next_element
            end
            endpoints
          end
        end

        def ssh_endpoint
          @ssh_endpoint ||= inputs_endpoints.detect { |ep| ep.attributes["name"] == "SSH" } rescue nil
        end

        def rdp_endpoint
          @rdp_endpoint ||= inputs_endpoints.detect { |ep| ep.attributes["name"] == "RDP" } rescue nil
        end

        def first_public_endpoint
          @first_public_endpoint ||= inputs_endpoints.detect { |ep| ep.attributes['isPublic'] == 'true'} rescue nil
        end

        def public_ip
          @public_ip ||= first_public_endpoint.attributes["loadBalancedPublicAddress"].split(":").first rescue nil
        end

        def public_ssh_port
          @public_ssh_port ||= ssh_endpoint.attributes["loadBalancedPublicAddress"].split(":").last.to_i rescue nil
        end

        def public_winrm_port
          @public_winrm_port ||= rdp_endpoint.attributes["loadBalancedPublicAddress"].split(":").last.to_i rescue nil
        end
      end

      def query_url(url)
        begin
          u = URI(url) # doesn't work on 1.8.7 didn't figure out why
          req = Net::HTTP::Get.new(u.request_uri)
          req['x-ms-agent-name'] = 'WALinuxAgent'
          req['x-ms-version'] = '2012-11-30'

          res = Net::HTTP.start(u.hostname, u.port) {|http|
            http.request(req)
          }
          res.body
        rescue Exception => e
          logger.debug("Unable to fetch azure metadata from #{url}: #{e.class}: #{e.message}")
        end
      end

      # Azure cloud has a metadata service (called the fabric controller). The ip of this
      # is passed in the response to DHCP discover packet as option 245. Proceed to
      # query the DHCP server, then parse its response for that option
      # See WALinuxAgent project as a reference, which does a bit more:
      #   - add then remove default route
      #   - disable then re-enable wicked-dhcp4 for distros that use it
      def build_dhcp_request
        req = DHCP::Discover.new
        logger.debug(req)
        req.pack
      end

      def endpoint_from_response(raw_pkt)
        packet = DHCP::Message.from_udp_payload(raw_pkt, :debug => false)
        logger.debug("Received response from Azure DHCP server:\n" + packet.to_s)
        option = packet.options.find { |opt| opt.type == 245 }
        if option
          return option.payload.join(".")
        else
          raise NoOption245Error
        end
      end

      def send_dhcp_request
        begin
          dhcp_send_packet = build_dhcp_request()

          sock = UDPSocket.new
          sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
          sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
          sock.bind('0.0.0.0', 68)
          sock.send(dhcp_send_packet, 0, '<broadcast>', 67)

          dhcp_rcv_packet = Timeout::timeout(3) { sock.recv(1024) }
          return dhcp_rcv_packet
        ensure
          sock.close() if sock && !sock.closed?
        end
      end

      def azure_fabric_controller_ip
        return @azure_endpoint if @azure_endpoint
        # Note a race condition exists where we can poll for metadata before dhclient
        # has gotten the lease. Make sure loops for a few minutes at least
        10.times do
          begin
            dhcp_res_pkt = send_dhcp_request()
            @azure_endpoint = endpoint_from_response(dhcp_res_pkt)
          rescue NoOption245Error => e
            raise "No option 245 in DHCP response, we don't appear to be in the Azure cloud"
          rescue Exception => e
            sleep 10
            # no-op for timeout
          end
          break if @azure_endpoint
        end
        raise "Could not get Azure endpoint" unless @azure_endpoint
        @azure_endpoint
      end

      # Separated out to mock easier
      def parse_shared_config(shared_config_content)
        SharedConfig.new(shared_config_content)
      end

      def fetch_azure_metadata

        base_url="http://#{azure_fabric_controller_ip}"

        logger.debug "Base url #{base_url}"

        goalstate = query_url("#{base_url}/machine/?comp=goalstate")
        container_id = goalstate.match(/<ContainerId>(.*?)<\/ContainerId>/)[1]
        instance_id  = goalstate.match(/<InstanceId>(.*?)<\/InstanceId>/)[1]
        incarnation = goalstate.match(/<Incarnation>(.*?)<\/Incarnation>/)[1]

        logger.debug  "\ngoalstate\n------------------"
        logger.debug  goalstate
        logger.debug "container_id #{container_id} instance_id #{instance_id} incarnation #{incarnation}"

        shared_config_content = query_url("#{base_url}/machine/#{container_id}/#{instance_id}?comp=config&type=sharedConfig&incarnation=#{incarnation}")
        logger.debug "\nsharedConfig\n------------------"
        logger.debug shared_config_content

        shared_config = parse_shared_config(shared_config_content)

        metadata = {
          'instance_id'     => shared_config.instance_id,
          'public_ip'       => shared_config.public_ip,
          'private_ip'      => shared_config.private_ip,
          'service_name'    => shared_config.service_name,
          'public_fqdn'     => "#{shared_config.service_name}.cloudapp.net"
        }

        metadata['public_ssh_port'] = shared_config.public_ssh_port if shared_config.public_ssh_port
        metadata['public_winrm_port'] = shared_config.public_winrm_port if shared_config.public_winrm_port
        metadata

      end

      # definitions for querying kinds of metadata by a simple path.
      DEFAULT_CLOUD_METADATA_ROOT_PATH = "cloud_metadata"
      DEFAULT_USER_METADATA_ROOT_PATH = "user_metadata"

      attr_accessor :cloud_metadata_cert_store, :cloud_metadata_cert_issuer
      attr_accessor :user_metadata_cert_store, :user_metadata_cert_issuer

      def initialize(options)
        super(options)
        raise ArgumentError.new("options[:cloud_metadata_root_path] is required") unless @cloud_metadata_root_path = options[:cloud_metadata_root_path]
        raise ArgumentError.new("options[:user_metadata_root_path] is required") unless @user_metadata_root_path = options[:user_metadata_root_path]

        @cloud_metadata_cert_store = options[:cloud_metadata_cert_store]
        @cloud_metadata_cert_issuer = options[:cloud_metadata_cert_issuer]

        @user_metadata_cert_store = options[:user_metadata_cert_store]
        @user_metadata_cert_issuer = options[:user_metadata_cert_issuer]
      end

      # Queries for metadata using the given path.
      #
      # === Parameters
      # path(String):: metadata path
      #
      # === Return
      # metadata(String):: query result or empty
      #
      # === Raises
      # QueryFailed:: on any failure to query
      def query(path)
        result = ""
        if path == @cloud_metadata_root_path
          result = fetch_azure_metadata
        elsif path == @user_metadata_root_path
          result = read_cert(@user_metadata_cert_store, @user_metadata_cert_issuer) if @user_metadata_cert_store && @user_metadata_cert_issuer
        else
          raise QueryFailed.new("Unknown path: #{path}")
        end
        result
      rescue QueryFailed
        raise
      rescue Exception => e
        raise QueryFailed.new(e.message)
      end

      # Nothing to do.
      def finish
        true
      end

      protected

      def read_cert(cert_store, cert_issuer)
        if ::RightScale::Platform.windows?
          read_cert_windows(cert_store, cert_issuer)
        else
          read_cert_linux(cert_store, cert_issuer)
        end
      end

      def read_cert_linux(cert_store, cert_issuer)
        begin
          data = File.read(cert_store)
          cert = OpenSSL::X509::Certificate.new(data)

          certificate_issuer = cert.issuer.to_s.split("/").sort
          certificate_issuer.shift
          raise QueryFailed.new("Certificate issuer does not match.") unless certificate_issuer == cert_issuer.split(", ").sort
          raise QueryFailed.new("Unexpected certificate subject format: #{cert.subject.to_s}") unless cert.subject.to_s[1..3] == "CN="

          result = Base64.decode64(cert.subject.to_s[4..-1].gsub('x0A',''))
        rescue Exception => e
          raise QueryFailed.new("Failed to retrieve metadata from cert given as \"#{cert_issuer}\" under \"#{cert_store}\"")
        end

        return result
      end

      READ_CERT_POWERSHELL_SCRIPT = <<EOF
# stop and fail script when a command fails.
$ErrorActionPreference = "Stop"

try
{
  # requires Win2008+
  if ([Int32]::Parse((Get-WmiObject Win32_OperatingSystem).Version.split('.')[0]) -lt 6)
  {
    throw "This version of Windows is not supported."
  }

  # check arguments.
  if ($args.length -lt 3)
  {
    write-output "Usage: read_cert <cert store> <cert issuer> <output file>"
    exit 101
  }
  $CERT_STORE = $args[0]
  $CERT_ISSUER = $args[1]
  $OUTPUT_FILE_PATH = $args[2]

  # normalizes a Distinguished Name (DN) to ensure that parts appear in a consistent order in
  # the DN string for comparison purposes. in Active Directory, DN parts are strictly ordered
  # to make a full path to an object but other use cases (cert issuer, etc.) may not be as strict.
  function NormalizeDN($dn)
  {
    [string]::join(',', ($dn.split(',') | foreach-object { $_.trim() } | sort-object))
  }

  # attempt to cert given by issuer (distinguished name) in the given cert store. select the most
  # recently issued cert matching the given issuer by sorting certs in descending 'not before'
  # order (i.e. last issued) and selecting first in the sorted array.
  $compare = NormalizeDN($CERT_ISSUER)
  $certs = @() + (get-item "$CERT_STORE\\*" | where-object { $compare -eq (NormalizeDN($_.issuer)) } | sort-object -Property notbefore -Descending)
  $cert = $certs[0]
  if ($NULL -eq $cert)
  {
    throw "Unable to find certificate matching ""$CERT_ISSUER"" under ""$CERT_STORE""."
  }

  # assumes that metadata is encoded in base-64 binary as .subject field of cert
  # in form 'CN=<base-64 metadata string>'. if we don't match this pattern,
  # then just bail out.
  $encodedMetadata = $cert.subject
  if (-not ($encodedMetadata.startsWith('CN=')))
  {
    throw "Unexpected cert subject format ""$encodedMetadata"""
  }
  # note that the base-64 string may or may not have double-quotes around it.
  # not sure how double-quotes get inserted into the middle of the CN= phrase
  # on Linux side (and not in Windows test), but life is a mystery.
  $encodedMetadata = ($encodedMetadata.substring(3, $encodedMetadata.length - 3)).trim('"')
  $decodedMetadata = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedMetadata)))
  $decodedMetadata | Out-File -Encoding ASCII $OUTPUT_FILE_PATH
}
catch
{
  $ErrorActionPreference = "Continue"
  write-error $_
  exit 100
}

exit 0
EOF

      def read_cert_windows(cert_store, cert_issuer)
        result = ''
        Dir.mktmpdir do |dir|
          script_file_path = ::File.normalize_path(::File.join(dir, 'read_cert.ps1'))
          output_file_path = ::File.normalize_path(::File.join(dir, 'output.txt'))
          ::File.open(script_file_path, "w") { |f| f.write READ_CERT_POWERSHELL_SCRIPT }
          cmd = ::RightScale::Platform.shell.format_shell_command(script_file_path, cert_store, cert_issuer, output_file_path)
          result = `#{cmd}`
          if $?.success?
            if ::File.file?(output_file_path)
              result = ::File.read(output_file_path)
            else
              result = result.to_s.strip
              result = "No data was read from cert given as \"#{cert_issuer}\" under \"#{cert_store}\"." if result.empty?
              raise QueryFailed.new(result)
            end
          else
            result = result.to_s.strip
            result = "Failed to retrieve metadata from cert given as \"#{cert_issuer}\" under \"#{cert_store}\"." if result.empty?
            raise QueryFailed.new(result)
          end
        end
        return result
      end

    end  # AzureMetadataSource

  end  # MetadataSources

end  # RightScale
