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

module RightScale

  module MetadataSources

    # Azure doesn't really have any sort of unified metadata service. It currently has three separate sources to stitch together for userdata and metadata:
    #   1. A cdrom drive is mounted at startup by the WALinuxAgent service. This has an xml file with Hostname, Username/password info, UserData (called CustomData). The CustomData is a newer thing which we don't use unfortunately, as it would be handy
    #   2. Certificate metadata source. Currently used ONLY for userdata. This is a proprietary "hacky" solution in which we stuff secret userdata in a X509 certificate attached to the instance at Launch time
    #   3. Azure has a metadata service with HostName, Networking information, Instance information, Plugin information, and some other goodies in its "fabric controller". This is XML served via a web service. The url of that web service is passed as "option 245" in the DHCP server response at bootup
    #   We currently use 2 for userdata and 3 for metadata above, though we'd like to use 1 for userdata and 3 for metadata and ditch our solution
    class AzureMetadataSource < MetadataSource

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
          result = read_cert(@cloud_metadata_cert_store, @cloud_metadata_cert_issuer) if @cloud_metadata_cert_store && @cloud_metadata_cert_issuer
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

    end  # CertificateMetadataSource

  end  # MetadataSources

end  # RightScale
