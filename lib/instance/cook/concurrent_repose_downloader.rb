require 'rbconfig'
require 'right_popen'

module RightScale
  class ConcurrentReposeDownloader

    def initialize
      @stdout_text = ""
      @stderr_text = ""
      @exit_status = nil
      @pid = nil
    end

    def download(type, uri, path, name, note, root_dir, servers)
      bundle = "/opt/rightscale/sandbox/bin/bundle"
      ruby = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["RUBY_INSTALL_NAME"] + RbConfig::CONFIG["EXEEXT"])
      worker = File.join(File.expand_path("..", __FILE__), "concurrent_repose_downloader_worker.rb")
      EM.next_tick do
        command = [bundle, 'exec', ruby, worker, type, uri, path, name, note, root_dir] + servers
        RightScale::RightPopen.popen3_async(
          command,
          :target         => self,
          :environment    => nil,
          :pid_handler    => :on_pid,
          :stdout_handler => :on_read_stdout,
          :stderr_handler => :on_read_stderr,
          :exit_handler   => :on_exit)
      end
    end

    def on_pid(pid)
      @pid = pid
    end

    def on_read_stdout(data)
      @stdout_text << data
    end

    def on_read_stderr(data)
      @stderr_text << data
    end

    def on_exit(status)
      @exit_status = status
    end

    def pid
      @pid
    end

    def stdout
      @stdout_text
    end

    def stderr
      @stderr_text
    end

    def status
      @exit_status
    end

    def self.process_output(downloaders, audit, log, &block)
      while downloaders.size > 0 do
        downloaders.each do |downloader|
          if downloader.status != nil
            messages = JSON.parse(downloader.stdout)
            messages.each do |message|
              case message[0]
              when 'report_failure'
                block.call(message[1], message[2])
              when 'append_info' || 'update_status'
                audit.send(message[0].to_sym, message[1])
              else
                log.send(message[0].to_sym, message[1])
              end
            end
            downloaders.delete(downloader)
          end
        end
      end
    end

  end
end

