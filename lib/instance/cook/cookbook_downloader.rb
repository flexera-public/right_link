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

module RightScale

  class CookbookDownloader < ReposeDownloader

    protected

    # Downloads an attachment from Repose
    #
    # The purpose of this method is to download the specified attachment from Repose
    # If a failure is encountered it will provide proper feedback regarding the nature
    # of the failure
    #
    # === Parameters
    # @param [String] Resource URI to parse and fetch
    # @param [String] Destination for fetched resource
    #
    # === Return
    # @return true Always returns true

    def _download(resource, dest)
      begin
        tarball = Tempfile.new(dest)
        tarball.binmode
        stream(resource) do |response|
          tarball << response
        end
        tarball.close
      rescue Exception => e
        tarball.close unless tarball.nil?
        raise e
      end
      tarball
    end

    # Return a sanitized value from given argument
    #
    # The purpose of this method is to return a value that can be securely
    # displayed in logs and audits
    #
    # === Parameters
    # @param [String] 'Resource' to parse
    #
    # === Return
    # @return [String] 'Resource' portion of resource provided

    def sanitize_resource(resource)
      resource.split('?').first.split('/').last
    end

  end

end