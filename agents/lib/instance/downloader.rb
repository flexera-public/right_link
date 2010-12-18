#
# Copyright (c) 2009 RightScale Inc
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

require 'fileutils'

module RightScale

  # Abstract download capabilities
  class Downloader

    DEFAULT_MAX_DOWNLOAD_RETRIES = 10

    # Initialize downloader with given retry period
    # When using backoff algorithm the retry period specifies the initial value, the value then gets
    # incremented after each retry exponentially until it reaches the specified maximum retry period
    #
    # === Parameters
    # retry_period(Integer):: Retry period in seconds - defaults to 10 seconds
    # use_backoff(Boolean):: Whether download should use a backoff algorithm to space retries - defaults to true
    # max_retry_period(Integer):: Maximum retry period in seconds, only meaningful when using backoff algorithm -
    #                             defaults to 5 minutes
    def initialize(retry_period = 10, use_backoff = true, max_retry_period = 5 * 60)
      @retry_period = retry_period
      @use_backoff = use_backoff
      @max_retry_period = max_retry_period if use_backoff
      platform = RightScale::RightLinkConfig[:platform]
      @found_curl = platform.filesystem.has_executable_in_path('curl')
    end

    # (Integer) Retry period in seconds
    attr_accessor :retry_period

    # (Boolean) Whether download should use a backoff algorithm to space retries
    attr_accessor :use_backoff

    # (Integer) Maximum retry period in seconds, only meaningful when using backoff algorithm
    attr_accessor :max_retry_period

    # (Integer) Size in bytes of last successful download (nil if none)
    attr_reader :size

    # (Integer) Speed in bytes/seconds of last successful download (nil if none)
    attr_reader :speed

    # Error message associated with last failure (nil if none)
    #
    # === Return
    # error(String):: Error message
    # nil:: No error occured during last download
    def error
      error = (@errors.nil? ||  @errors.empty?) ? nil : @errors.join("\n")
    end

    # Was last download successful?
    #
    # === Return
    # true:: If last download was successful or there was no download yet
    # false:: Otherwise
    def successful?
      error.nil?
    end

    # Download file synchronously and report on success, download size and download speed.
    # Use successful, size and speed to query about last download.
    # If last download failed, use error to retrieve error message.
    # Requires 'curl' to be available on PATH.
    #
    # === Parameters
    # url(String):: URL to downloaded file
    # dest(String):: Path where file should be saved on disk
    # username(String):: Optional HTTP basic authentication username
    # password(String):: Optional HTTP basic authentication password
    # max_retries(Integer):: Maximum number of retries - defaults to DEFAULT_MAX_DOWNLOAD_RETRIES
    #
    # === Block
    # Call (optional) passed in block after each unsuccessful download attempt.
    # Block must accept one argument corresponding to the last returned http code.
    #
    # === Return
    # true:: Download was successful
    # false:: Download failed
    def download(url, dest, username=nil, password=nil, max_retries=DEFAULT_MAX_DOWNLOAD_RETRIES)
      @errors = []
      retry_count = error_code = 0
      success = false
      reset_wait_time_span

      @errors << 'curl is not installed' unless @found_curl

      @errors << "destination file '#{dest}' is a directory" if File.directory?(dest)
      begin
        FileUtils.mkdir_p(File.dirname(dest)) unless File.directory?(File.dirname(dest))
      rescue Exception => e
        @errors << e.message
      end

      return false unless @errors.empty?

      # format curl command and redirect stderr away.
      #
      # note: ensure we use double-quotes (") to surround arguments on command
      # line because single-quotes (') are literals in windows.
      platform = RightScale::RightLinkConfig[:platform]
      user_opt = username && password ? "--user \"#{username}:#{password}\"" : ""
      dest = platform.filesystem.long_path_to_short_path(dest)
      cmd = "curl --fail --silent --show-error --insecure --location --connect-timeout 300 --max-time 3600 --write-out \"%{http_code} %{size_download} %{speed_download}\" #{user_opt} --output \"#{dest}\" \"#{url}\""
      cmd = platform.shell.format_redirect_stderr(cmd)
      begin
        out = `#{cmd}`
        out = out.split
        success = $?.success? && out.size == 3
        if success
          @size = out[1].to_i
          @speed = out[2].to_i
          @last_url = url
          return true
        else
          retry_count += 1
          error_code = out[0].to_i
          yield error_code if block_given?
          sleep wait_time_span
        end
      end until success || retry_count >= max_retries
      unless success
        @errors << "#{retry_count} download attempts failed, last HTTP response code was #{error_code}"
        return false
      end
      true
    end

    # Message summarizing last successful download details
    #
    # === Return
    # details(String):: Message with last url, download size and speed
    def details
      "Downloaded #{sanitize_uri(@last_url)} (#{ scale(size.to_i).join(' ') }) at #{ scale(speed.to_i).join(' ') }/s"
    end

    protected

    # Calculate wait time span before next download retry, takes into account retry period and whether backoff
    # algorithm should be used
    #
    # === Return
    # time_span(Integer):: Number of seconds algorithm should wait before proceeding with next download attempt
    def wait_time_span
      return @retry_period unless @use_backoff
      time_span = [ 2 ** @iteration * @retry_period, @max_retry_period ].min
      @iteration += 1
      time_span
    end

    # Reset backoff algorithm
    #
    # === Return
    # true:: Always return true
    def reset_wait_time_span
      @iteration = 0
      true
    end

    # Return scale and scaled value from given argument
    # Scale can be B, KB, MB or GB
    #
    # === Return
    # scaled(Array):: First element is scaled value, second element is scale ('B', 'KB', 'MB' or 'GB')
    def scale(value)
      scaled = case value
        when 0..1023
          [value, 'B']
        when 1024..1024**2 - 1
          [value / 1024, 'KB']
        when 1024^2..1024**3 - 1
          [value / 1024**2, 'MB']
        else
          [value / 1024**3, 'GB']
      end
    end

    def sanitize_uri(uri)
      begin
        uri = URI.parse(uri)
        return "#{uri.scheme}://#{uri.host}#{uri.path}" 
      rescue Exception => e
        return "file"
      end
    end
  end
end
