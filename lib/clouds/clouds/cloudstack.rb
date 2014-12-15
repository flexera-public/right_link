#
# Copyright (c) 2011 RightScale Inc
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


module RightScale::Clouds
  class Cloudstack < RightScale::Cloud
    # set abbreviation for env var generation to be same as ec2 for scripters.
    def abbreviation
      "ec2"
    end
    
    def metadata_host
      "http://#{dhcp_lease_provider}"
    end

    def metadata_url
      "/latest/meta-data"
    end

    def userdata_url
      "/latest/user-data"
    end

    def fetcher
      @fetcher ||= RightScale::MetadataSources::HttpMetadataSource.new(@options)
    end

    def finish
      @fetcher.finish() if @fetcher
    end

    def metadata
      metadata_keys = %w{service-offering availability-zone local-ipv4 local-hostname instance-id}
      metadata = {}
      metadata_keys.each do |k|
        val = fetcher.get(metadata_host + metadata_url + "/" + k)
        metadata[k] = val
      end
    end

    def userdata_raw
      fetcher.get(metadata_host = userdata_url)    
    end

    def lease_file_locations
      %w{
        /var/lib/dhclient/dhclient--eth0.lease 
        /var/lib/dhcp/dhclient.eth0.leases 
        /var/lib/dhcp3/dhclient.eth0.leases 
        /var/lib/dhclient/dhclient-eth0.leases 
        /var/lib/dhclient-eth0.leases 
        /var/lib/dhcpcd/dhcpcd-eth0.info
      }
    end

    def dhcp_lease_provider
      if platform.windows?
        timeout = Time.now + 5 * 60  # 5 minutes
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
        leases_file = lease_file_locations.find { |dhcpconfig| File.exist?(dhcpconfig) }
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
      fail("Cannot determine dhcp lease provider for cloudstack instance")
    end
  end
end

