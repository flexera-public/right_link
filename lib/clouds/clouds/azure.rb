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

# Location for injected certificate
CERT_FILE = platform.windows? ? 'cert:/LocalMachine/My' : '/var/lib/waagent/Certificates.pem'

# Windows changes the ST=CA portion of our issuer name to S=CA at some point.
ISSUER_STATE_KEY = platform.windows? ? 'S' : 'ST'

# dependencies.

metadata_source 'metadata_sources/azure_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer',
                 'metadata_writers/ruby_metadata_writer',
                 'metadata_writers/shell_metadata_writer'

# set abbreviation for non-RS env var generation
abbreviation :azure


# RightApi API version for use in X-API-Version header
API_VERSION = "1.5"

# Default time to wait for HTTP connection to open
DEFAULT_OPEN_TIMEOUT = 2

# Default time to wait for response from request, which is chosen to be 5 seconds greater
# than the response timeout inside the RightNet router
DEFAULT_REQUEST_TIMEOUT = 5

# Retrieve new user-data from RightApi
#
# @param [String] RigthtApi url
# @param [String] Client ID
# @param [String] Client Secret
# @param [Block] Yield on block with retieved data
#
# @return [TrueClass] always true
def retrieve_updated_data(api_url, client_id, client_secret)
  require 'right_agent'
  data = nil
  options = {
    :api_version => API_VERSION,
    :open_timeout => DEFAULT_OPEN_TIMEOUT,
    :request_timeout => DEFAULT_REQUEST_TIMEOUT,
    :filter_params => [:client_secret] }
  url = URI.parse(api_url)
  http_client = RightScale::BalancedHttpClient.new([url.to_s], options)
  begin
    response = http_client.post("/oauth2", {
      :client_id => client_id.to_s,
      :client_secret => client_secret,
      :grant_type => "client_credentials" } )
    response = SerializationHelper.symbolize_keys(response)
    access_token = response[:access_token]
    raise "Could not authoried on #{api_url} using oauth2" if access_token.nil?

    response = http_client.get("/user_data", {
      :client_id => client_id.to_s,
      :client_secret => client_secret },
       { :headers => {"Authorization" => "Bearer #{access_token}" } })
    data = response.to_s
    http_client.close("Updated user-data has been gotten")
  rescue
    http_client.close($!.message)
  end
  raise "Updated user-data is empty" if data.nil?
  yield data
  true
end

# Parses azure user metadata into a hash.
#
# === Parameters
# tree_climber(MetadataTreeClimber):: tree climber
# data(String):: raw data
#
# === Return
# result(Hash):: Hash-like leaf value
def get_updated_userdata(tree_climber, data)
  result = tree_climber.create_branch
  ::RightScale::CloudUtilities.split_metadata(data.strip, '&', result)
  api_url       = "https://#{result['RS_server']}/api"
  client_id     = result['RS_rn_id']
  client_secret = result['RS_rn_auth']
  retrieve_updated_data(api_url, client_id , client_secret) do |updated_data|
    ::RightScale::CloudUtilities.split_metadata(updated_data.strip, '&', result)
  end
  result
end

def parse_metadata(tree_climber, data)
  result = tree_climber.create_branch
  data.each do |k, v|
    # Make sure we coerce into strings. The json blob returned here auto-casts
    # types which will mess up later steps
    result[k.to_s.strip] = v.to_s.strip
  end
  result
end

def wait_for_instance_ready
  if platform.linux?
    STDOUT.puts "Waiting for instance to appear ready."
    until File.exist?(CERT_FILE) && File.mtime(CERT_FILE).to_f > platform.shell.booted_at.to_f do
      sleep(1)
    end
    STDOUT.puts "Instance appears ready."
  end
end

# defaults.
default_option([:metadata_source, :user_metadata_cert_store], CERT_FILE)
default_option([:metadata_source, :user_metadata_cert_issuer], "O=RightScale, C=US, #{ISSUER_STATE_KEY}=CA, CN=RightScale User Data")

default_option([:user_metadata, :metadata_tree_climber, :create_leaf_override], method(:get_updated_userdata))
default_option([:cloud_metadata, :metadata_tree_climber, :create_leaf_override], method(:parse_metadata))
default_option([:cloud_metadata, :metadata_tree_climber, :has_children_override], lambda { |*| false } )
default_option([:cloud_metadata, :metadata_writers, :ruby_metadata_writer, :generation_command], cloud_metadata_generation_command)
