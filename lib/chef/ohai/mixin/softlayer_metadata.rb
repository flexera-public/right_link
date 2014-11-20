require 'net/http'

module ::Ohai::Mixin::SoftlayerMetadata
  SOFTLAYER_API_QUERY_URL='https://api.service.softlayer.com/rest/v3'

  def fetch_metadata
    metadata  = {
      'public_fqdn' => api_query("SoftLayer_Resource_Metadata/getFullyQualifiedDomainName.txt"),
      'local_ipv4' => api_query("SoftLayer_Resource_Metadata/getPrimaryBackendIpAddress.txt"),
      'public_ipv4' => api_query("SoftLayer_Resource_Metadata/getPrimaryIpAddress.txt")
    }
    metadata
  end

  def api_query(query)
    begin
      u = URI("#{SOFTLAYER_API_QUERY_URL}/#{query}")
      res = Net::HTTP.start(u.hostname, u.port, :use_ssl => true) {|http|
        req = Net::HTTP::Get.new u.request_uri
        res = http.request(req)
      }
      result = res.body
    rescue Exception => e
      ::Ohai::Log.error("Unable to fetch softlayer metadata from #{u}: #{e.class}: #{e.message}")
      nil
    end
  end
end