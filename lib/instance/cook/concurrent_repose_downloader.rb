require 'right_popen'
require 'shellwords'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'agent_config'))

module RightScale
  class ConcurrentDownloadException < Exception
    attr_reader :exception_class, :message, :file_name
    def initialize(exception_class, message, file_name)
      @exception_class = exception_class
      @message = message
      @file_name = file_name
    end
  end
  class ConcurrentReposeDownloader
    include RightSupport::Log::Mixin

     MAX_CONCURRENCY = 8
     def initialize(hostnames, audit)
       @hostnames = hostnames
       @running_downloads = 0
       @download_queue = []
       @audit = audit
       @success = true
     end

     def download(resource, out_file)
       if @running_downloads < MAX_CONCURRENCY
         run_download(resource, out_file)
       else
         @download_queue.push([resource, out_file])
       end
     end

     def join
       sleep 0.1 while @running_downloads > 0
       @success
     end

protected
     def stdout_handler(data)
       data = JSON.parse(data) rescue nil
       return unless data
       data = RightScale::SerializationHelper.symbolize_keys(data)
       data.each do |type, msg|
         case type
         when :audit
           @audit.append_info(msg)
         else
           logger.send(type, msg)
         end
       end
     end

     def stderr_handler(data)
       data = JSON.parse(data) rescue nil
       return unless data
       data = RightScale::SerializationHelper.symbolize_keys(data)
       raise ConcurrentDownloadException.new(data[:exception][:class], data[:exception][:message], data[:exception][:file_name])
     end

     def on_exit(status)
       @running_downloads -= 1
       @success = !!status.success?
       run_download(*@download_queue.shift) if @success && !@download_queue.empty?
     end

    # Path to 'repose_get' ruby script
    #
    # === Return
    # path(String):: Path to ruby script used to download from repose
    def repose_get_path
      relative_path = File.join(File.dirname(__FILE__), '..', '..', '..', 'bin', 'repose_get')
      return File.normalize_path(relative_path)
    end

    # Command line fragment for the repose_get script path and any arguments.
    #
    # === Return
    # path_and_arguments(String):: repose_get path plus any arguments properly quoted.
    def repose_get_and_argments(resource, out_file)
      args = ["--resource #{Shellwords.escape(resource)}",
              "--out-file #{Shellwords.escape(out_file)}"]
      args += @hostnames.map { |hostname| Shellwords.escape(hostname) }
      "\"#{repose_get_path}\" #{args.join(" ")}"
    end

    def repose_get_cmd(resource, out_file)
      ruby_exe_path = File.normalize_path(AgentConfig.ruby_cmd)
      ruby_exe_path = ruby_exe_path.gsub("/", "\\") if RightScale::Platform.windows?
      "#{ruby_exe_path} #{repose_get_and_argments(resource, out_file)}"
    end

    def run_download(resource, out_file)
      @running_downloads += 1
      RightScale::RightPopen.popen3_async(
        repose_get_cmd(resource, out_file),
        :target         => self,
        :environment    => nil,
        :stdout_handler => :stdout_handler,
        :stderr_handler => :stderr_handler,
        :exit_handler   => :on_exit)
    end
  end
end
