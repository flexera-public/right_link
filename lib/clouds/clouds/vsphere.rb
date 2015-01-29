#
# Copyright (c) 2013 RightScale Inc
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
require 'right_agent'

module RightScale::Clouds
  class Vsphere < RightScale::Cloud
    class VmToolsException < RuntimeError; end

    VSCALE_DEFINITION_VERSION = 0.3

    DISCOVERING_REGEXP  = /\=discovering$/

    def abbreviation
      "vs"
    end

    def vmtoolsd
      RightScale::Platform.windows? ? File.expand_path('VMware/VMware Tools/vmtoolsd.exe', ENV['ProgramW6432']).gsub('/',"\\")  : 'vmtoolsd'
    end

    def fetch_timeout
      15*60
    end

    def retry_delay
      5
    end

    def vsphere_metadata_location
      File.join(RightScale::Platform.filesystem.spool_dir, 'vsphere')
    end

    def metadata_file
      File.join(vsphere_metadata_location, "meta.txt")
    end

    def userdata_file
      File.join(vsphere_metadata_location, "user.txt")
    end

    def fetcher
      @fetcher ||= RightScale::MetadataSources::FileMetadataSource.new(@options)
    end

    def metadata
      data = fetcher.get(metadata_file)
      RightScale::CloudUtilities.split_metadata(data, "\n", "=")
    end

    def userdata_raw
      raw_data = fetcher.get(userdata_file)
      raw_data.split("\n").join("&")
    end

    def requires_network_config?
      true
    end

    def write_error(message)
      logger.error(message) #STDERR.puts message
    end

    def write_debug(message)
      logger.debug(message) #STDERR.puts message
    end

    def write_output(message)
      logger.info(message) #STDOUT.puts message
    end

    def run_command(cmd)
      output = `#{cmd}`
      return [output, $?.exitstatus]
    end

    def query_data(type)
      cmd = "\"#{vmtoolsd}\" \"--cmd=info-get guestinfo.#{type}\" 2>&1"
      output, status = run_command(cmd)
      if status == 0
        if output.include?("No value found")
          output = ""
        end
        return output.gsub("&", "\n").strip
      else
        raise RightScale::Clouds::Vsphere::VmToolsException, "Failed to run fetch command: #{cmd} status(#{status}) output(#{output})"
      end
    end

    def save(file, content)
      output_dir = File.dirname(file)
      FileUtils.mkdir_p(output_dir)
      File.open(file, File::RDWR|File::CREAT, 0644) do |f|
        f.flock(File::LOCK_EX)
        f.rewind
        f.write(content)
        f.flush
        f.truncate(f.pos)
      end
    end

    def save_data(metadata, userdata)
      begin
        save(metadata_file, metadata)
        save(userdata_file, userdata)
        write_output "Metadata has been saved."
      rescue
        return ActionResult.new(:exitstatus => 10, :error => "Failed to save metadata : #{$!}")  
      end
    end

    def fetch_thread(type)
      Thread.new do
        while true
          begin
            data = query_data(type)
            if data =~ DISCOVERING_REGEXP
              sleep retry_delay
            else
              break
            end
          rescue RightScale::Clouds::Vsphere::VmToolsException => e
            write_debug(e.message)
            sleep retry_delay
          end
        end
        write_output "Metadata has been fetched type: #{type}."
        data
      end
    end

    def wait_for_instance_ready
      started_at = Time.now.to_i

      user_thread = fetch_thread('userdata')
      meta_thread = fetch_thread('metadata')

      while (Time.now.to_i - started_at) < fetch_timeout
        unless user_thread.alive? || meta_thread.alive?
          save_data(meta_thread.value, user_thread.value)
          return ActionResult.new
        end
        write_debug "Metadata is not ready, sleeping"
        sleep retry_delay
      end

      user_thread.terminate
      meta_thread.terminate

      error_msg = "Fetch metadata failed due to timeout in #{fetch_timeout} seconds"
      return ActionResult.new(:exitstatus => 10, :error => error_msg)      
    end


    def finish
      @fetcher.finish() if @fetcher
    end

  end

end
