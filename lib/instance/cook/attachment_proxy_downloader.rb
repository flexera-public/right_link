#
# Copyright (c) 2009-2012 RightScale Inc
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

class String
  unless method_defined?(:starts_with?)
    def starts_with?(prefix)
      prefix = prefix.to_s
      self[0, prefix.length] == prefix
    end
  end
end

module RightScale

  class AttachmentProxyDownloader < AttachmentDownloader

    # Environment variables to examine for proxy settings, in order.
    PROXY_ENVIRONMENT_VARIABLES = ['HTTPS_PROXY', 'HTTP_PROXY', 'http_proxy', 'ALL_PROXY']

    # Initializes an AttachmentProxyDownloader with a list of hostnames
    #
    # The purpose of this method is to instantiate an AttachmentProxyDownloader
    #
    # === Parameters
    # @param <[String]> Hostnames to resolve
    #
    # === Return
    # @return [AttachmentProxyDownloader]

    def initialize(hostnames)
      super
      proxy_var = PROXY_ENVIRONMENT_VARIABLES.detect { |v| ENV.has_key?(v) }
      @proxy = ENV[proxy_var].match(/^[[:alpha:]]+:\/\//) ? URI.parse(ENV[proxy_var]) : URI.parse("http://" + ENV[proxy_var])
    end

    protected

    # Instantiates an HTTP Client
    #
    # The purpose of this method is to create an HTTP Client that will be used to
    # make requests in the download method
    #
    # === Return
    # @return [RestClient]

    def get_http_client
      RestClient.proxy = @proxy.to_s
      RestClient
    end

  end

end