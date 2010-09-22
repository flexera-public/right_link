#
# Copyright (c) 2010 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), 'metadata_provider'))
require File.expand_path(File.join(File.dirname(__FILE__), 'cloud_info'))

module RightScale

  # Implements MetadataProvider for EC2.
  class Ec2MetadataProvider < MetadataProvider

    # === Parameters
    # options[:retry_delay_secs](float):: retry delay in seconds.
    #
    # options[:max_curl_retries](int):: max attempts to invoke cURL for a given URL before failure.
    #
    # options[:logger](Logger):: logger (required)
    def initialize(options)
      @retry_delay_secs = options[:retry_delay_secs] || 1
      @max_curl_retries = options[:max_curl_retries] || 10
      raise "options[:logger] is required" unless @logger = options[:logger]
    end

    # Fetches EC2 metadata for the current instance.
    #
    # === Returns
    # metadata(Hash):: tree of metadata
    def metadata
      url = RightScale::CloudInfo.metadata_server_url + '/latest/meta-data/'
      return recursive_fetch_metadata(url)
    end

    private

    CURL_OPTIONS = "-s -S -f -L --retry 4294967295 --retry-max-time 240 --max-time 10"

    # Recursively grabs a tree of metadata and uses it to populate a tree of
    # metadata.
    #
    # === Parameters
    # url(String):: URL to query for metadata.
    #
    # === Returns
    # tree_metadata(Hash):: tree of metadata
    def recursive_fetch_metadata(url)

      # query URL expecting a plain text list of URL subpaths delimited by
      # newlines.
      tree_metadata = {}
      sub_paths = curl_get(url)
      sub_paths.each do |sub_path|
        sub_path = sub_path.strip
        unless sub_path.empty?

          # an equals means there is a subtree to query by the key preceeding
          # the equals sign.
          # example: /public_keys/0=pubkey_name
          equals_index = sub_path.index('=')
          if equals_index
            sub_path = sub_path[0,equals_index]
            sub_path += "/"
          end

          # a URL ending with forward slash is a branch, otherwise a leaf
          if sub_path =~ /\/$/
            tree_metadata[sub_path.chomp('/')] = recursive_fetch_metadata(url + sub_path)
          else
            tree_metadata[sub_path] = curl_get(url + sub_path)
          end

        end
      end

      return tree_metadata
    end

    # Invokes cURL for metadata with retry logic.
    #
    # === Parameters
    # url(String):: URL to query for metadata.
    #
    # === Returns
    # out(String):: raw output from cURL
    def curl_get(url)
      retry_count = 0
      cmd = "curl #{CURL_OPTIONS} #{url} 2>&1"
      @logger.debug(cmd)
      while true
        out = `#{cmd}`
        if $?.success?

          # EC2 is a REST API which can respond with multi-line XHTML containing
          # error details if there are currently too many connections to the
          # server, etc. cURL will return zero in this case which requires our
          # code to check for failure. the expected format for a branch is a
          # plain-text, newline-delimited list of valid URL subpaths and so any
          # space characters in the response indicate a failure requiring retry.
          # the caveat is that leaf values can contain spaces and newlines but
          # are not expected to have an HTTP header as is the case with error
          # pages.
          #
          # FIX: does this handle all cases or do we need one or more regular
          # expressions to match EC2 error replies (assuming we will always know
          # what they look like)? have yet to find documentation on such errors.
          out.strip!
          if out.index(' ') && (/\/$/.match(url) || (out.index("\n") && out.index('HTTP/1.')))
            @logger.warn("cURL succeeded but response contained error information:\n#{out}")
          else
            return out
          end
        else
          @logger.error("cURL exited with status (#{$?.exitstatus}), returned:\n#{out}")
        end

        # retry, if allowed.
        retry_count += 1
        if retry_count < @max_curl_retries
          @logger.info("Retrying \"#{url}\"...")
          sleep(@retry_delay_secs)
        else
          raise "cURL retry limit exceeded, giving up and using cached values."
        end
      end
    end
  end

end
