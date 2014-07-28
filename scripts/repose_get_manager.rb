require 'trollop'
require 'logger'
require 'right_agent'
require File.expand_path(File.join(File.dirname(__FILE__), '..','lib', 'instance', 'cook', 'repose_downloader'))
require File.expand_path(File.join(File.dirname(__FILE__), '..','lib', 'right_link', 'version'))

module RightScale
  class ReposeGetLogger < Logger
    def initialize; end

    def add(severity, progname = nil, message = nil, &block)
      data = {}
      data[Log.level_to_sym(severity)] = message
      STDOUT.puts data.to_json
      STDOUT.flush
    end
  end

  class RightLinkReposeGetManager
    def self.run
      m = RightLinkReposeGetManager.new
      m.control(m.parse_args)
    end

    def audit(msg)
      data = {}
      data[:audit] = msg
      STDOUT.puts data.to_json
      STDOUT.flush
    end

    def control(options)
      downloader = ReposeDownloader.new(options[:hostnames])
      downloader.logger = ReposeGetLogger.new
      resource = options[:resource]
      out_file = options[:out_file]

      begin
        downloader.download(resource) do |response|
          FileUtils.mkdir_p(File.dirname(out_file))
          File.open(out_file, "wb") { |f| f.write(response) }
          audit(downloader.details)
        end
      rescue Exception => e
        data = {:exception => {:class => e.class.name, :message => e.message, :file_name => out_file}}
        STDERR.puts data.to_json
        STDERR.flush
      end
    end

    def parse_args
      parser = Trollop::Parser.new do
        opt :resource, "", :type => :string
        opt :out_file, "", :type => :string
      end

      options = parser.parse
      options[:hostnames] = ARGV.dup
      options
    end
  end
end
