#
# Copyright (c) 2010-2014 RightScale Inc
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

module ::Ohai::Mixin::RightLink
  module Metadata
    # Top dir for meta-data, each file is key and content if value.
    ROOT_DIR = File.join('/','var','spool','cloud','meta-data')

    # Fetch metadata form dir (recursevly).
    # each file name is a key and value it's content
    def fetch_from_dir(metadata_dir, metadata = {})
      raise "Meta-data dir does not exist: #{metadata_dir}" unless File.directory?(metadata_dir)
      ::Ohai::Log.debug('Fetching from meta-data dir: #{metadata_dir}')
      metadata = {}
      Dir.foreach(metadata_dir) do |name|
        next if name =='.' || name  == '..'
        metadata_file = File.join(metadata_dir,name)
        key = name.gsub(/\-/,'_')
        if File.directory?(metadata_file)
          metadata[key] = fetch_from_dir(metadata_file, {})
        else
          value = File.read(metadata_file)
          metadata[key] = value
        end
      end
      metadata
    end

    # Fetch metadata
    def fetch_metadata
      ::Ohai::Log.debug('Fetching metadata')
      metadata = fetch_from_dir(ROOT_DIR)
      ::Ohai::Log.debug("Fetched metadata: #{metadata.inspect}")
      metadata
    rescue
      ::Ohai::Log.error("Fetching metadata failed: #{$!}")
      false
    end

    # Searches for a file containing dhcp lease information.
    def dhcp_lease_provider
      logger = ::Ohai::Log
      if os == 'windows'
        timeout = Time.now + 20 * 60  # 20 minutes
        while Time.now < timeout
          ipconfig_data = `ipconfig /all`
          match_result = ipconfig_data.match(/DHCP Server.*\: (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/)
          unless match_result.nil? || match_result[1].nil?
            return match_result[1]
          end
          # it may take time to resolve the DHCP Server for this instance, so sleepy wait.
          logger.info("ipconfig /all did not contain any DHCP Servers. Retrying in 10 seconds...")
          sleep 10
        end
      else
        leases_file = %w{/var/lib/dhcp/dhclient.eth0.leases /var/lib/dhcp3/dhclient.eth0.leases /var/lib/dhclient/dhclient-eth0.leases /var/lib/dhclient-eth0.leases /var/lib/dhcpcd/dhcpcd-eth0.info}.find{|dhcpconfig| File.exist?(dhcpconfig)}
        unless leases_file.nil?
          lease_file_content = File.read(leases_file)

          dhcp_lease_provider_ip = lease_file_content[/DHCPSID='(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'/, 1]
          return dhcp_lease_provider_ip unless dhcp_lease_provider_ip.nil?

          # leases are appended to the lease file, so to get the appropriate dhcp lease provider, we must grab
          # the info from the last lease entry.
          #
          # reverse the content and reverse the regex to find the dhcp lease provider from the last lease entry
          lease_file_content.reverse!
          dhcp_lease_provider_ip = lease_file_content[/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}) reifitnedi-revres-pchd/, 1]
          return dhcp_lease_provider_ip.reverse unless dhcp_lease_provider_ip.nil?
        end
      end
      # no known defaults so we must fail at this point.
      raise "Cannot determine dhcp lease provider for cloudstack instance"
    end

  end
end
