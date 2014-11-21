require 'net/https'

# http://sldn.softlayer.com/reference/services/SoftLayer_Resource_Metadata
module ::Ohai::Mixin::SoftlayerMetadata
  SOFTLAYER_API_QUERY_URL='https://api.service.softlayer.com/rest/v3.1/SoftLayer_Resource_Metadata'

  def fetch_metadata
    metadata  = {
      'public_fqdn'   => fetch_metadata_item("getFullyQualifiedDomainName.txt"),
      'local_ipv4'    => fetch_metadata_item("getPrimaryBackendIpAddress.txt"),
      'public_ipv4'   => fetch_metadata_item("getPrimaryIpAddress.txt"),
      'region'        => fetch_metadata_item("getDatacenter.txt"),
      'instance_id'   => fetch_metadata_item("getId.txt")
    }

    metadata
  end

  # We ship curl's CA bundle with rightlink. 
  def ca_file_location
    File.expand_path("../../../../instance/cook/ca-bundle.crt", __FILE__)
  end

  def fetch_metadata_item(item)
    begin
      full_url = "#{SOFTLAYER_API_QUERY_URL}/#{item}"
      u = URI(full_url)
      net = Net::HTTP.new(u.hostname, u.port)
      net.ssl_version = "TLSv1"
      net.use_ssl = true
      net.ca_file = ca_file_location
      res = net.get(u.request_uri)
      if res.code.to_i.between?(200,299) 
        res.body
      else
        ::Ohai::Log.error("Unable to fetch item #{full_url}: status (#{res.code}) body (#{res.body})")
        nil
      end
    rescue Exception => e
      ::Ohai::Log.error("Unable to fetch softlayer metadata from #{u}: #{e.class}: #{e.message}")
      nil
    end
  end
end
