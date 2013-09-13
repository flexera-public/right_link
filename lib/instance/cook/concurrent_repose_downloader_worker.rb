#ConcurrentReposeDownloader Worker
#
# Using examples according to current download algorithm in ExecuteSequence
#
#   Attachments
#     ruby concurent_repose_downloader_worder.rb attachment a.url attach_dir a.file_name "" "" bundle.repose_servers
#
#   Cookbooks
#     ruby concurent_repose_downloader_worder.rb cookbook /cookbooks/#{cookbook.hash} cache_dir #{cookbook.hash.split('?').first}.tar "'name' (tag)" root_dir bundle.repose_servers
#
require 'json'
require 'right_support'
require File.join(File.expand_path("..", __FILE__), "repose_downloader.rb")

type      = ARGV.shift
uri       = ARGV.shift
path      = ARGV.shift
name      = ARGV.shift
note      = ARGV.shift
root_dir  = ARGV.shift
servers   = ARGV

class FakeLogger

  def initialize
    @messages = []
  end

  def messages
    @messages
  end

  def info(message)
    @messages.push([:info,message])
  end

  def error(message)
    @messages.push([:error,message])
  end

  def warn(message)
    @messages.push([:warn,message])
  end

  ef debug(message)
    @messages.push([:debug,message])
  end

  def trace(message)
    @messages.push([:trace,message])
  end

  def update_status(message)
    @messages.push([:update_status,message])
  end

  def append_info(message)
    @messages.push([:append_info,message])
  end

  def report_failure(message,emessage)
    @messages.push([:report_failure,message,emessage])
  end

end

downloader        = ReposeDownloader.new(servers)
downloader.logger = FakeLogger.new

if note.size > 0
  note = " #{note}"
else
  note = nil
end

downloader.logger.append_info("Downloading #{type} '#{name}'#{note} into '#{file}'")
file = File.join(path, name)

begin
  FileUtils.mkdir_p(path) unless File.directory?(path)
  File.open(file, "ab") do |f|
    downloader.download(uri) do |response|
      f << response
    end
    downloader.logger.append_info(downloader.details)
  end
rescue Exception => e
  File.unlink(file) if File.exists?(file)
  downloader.logger.append_info("Repose download failed: #{e.message}.")
  if e.kind_of?(ReposeDownloader::DownloadException) && e.message.include?("Forbidden")
    downloader.logger.append_info("Often this means the download URL has expired while waiting for inputs to be satisfied.")
  end
  downloader.logger.report_failure("Failed to download #{type} '#{name}'", e.message)
end

if type == 'cookbook'
  downloader.logger.append_info("Success; unarchiving cookbook")
  # The local basedir is the faux "repository root" into which we extract all related
  # cookbooks in that set, "related" meaning a set of cookbooks that originally came
  # from the same Chef cookbooks repository as observed by the scraper.
  #
  # Even though we are pulling individually-packaged cookbooks and not the whole repository,
  # we preserve the position of cookbooks in the directory hierarchy such that a given cookbook
  # has the same path relative to the local basedir as the original cookbook had relative to the
  # base directory of its repository.
  #
  # This ensures we will be able to deal with future changes to the Chef merge algorithm,
  # as well as accommodate "naughty" cookbooks that side-load data from the filesystem
  # using relative paths to other cookbooks.
  FileUtils.mkdir_p(root_dir)
  Dir.chdir(root_dir) do
    # note that Windows uses a "tar.cmd" file which is found via the PATH
    # used by the command interpreter.
    cmd = "tar xf #{file.inspect} 2>&1"
    downloader.logger.debug(cmd)
    output = `#{cmd}`
    downloader.logger.append_info(output)
    unless $?.success?
      downloader.logger.report_failure("Unknown error", SubprocessFormatting.reason($?))
    end
  end
end

puts download.logger.messages.to_json

