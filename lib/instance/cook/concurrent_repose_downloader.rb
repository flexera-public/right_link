require 'rbconfig'

module RightScale
  class ConcurrentReposeDownloader
    def self.download()
      ruby = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["RUBY_INSTALL_NAME"] + RbConfig::CONFIG["EXEEXT"])
      worker = File.join(File.expand_path("..", __FILE__), "concurrent_repose_downloader_worker.rb")
      "bundle exec #{ruby} #{worker}"
    end
  end
end
