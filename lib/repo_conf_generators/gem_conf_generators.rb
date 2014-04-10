#
#
# Copyright (c) 2009-2011 RightScale Inc
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

module Gems

  # Wrapper for the 'gem sources' command
  # 
  # @param [String] absolute path to config file to edit, i.e. '/etc/gemrc'
  # @param [String] gem sources command to run, such as "--list"
  def self.src_cmd(cfg, command)
    sandbox_dir = ::RightScale::Platform.filesystem.sandbox_dir

    res = `#{sandbox_dir}/bin/gem --config-file #{cfg} sources #{command}`
    unless $?.success?
      raise "Error #{RightScale::SubprocessFormatting.reason($?)} executing: `#{command}`: #{res}"
    end
    res
  end

  # Add a list of urls to a gem config file
  # 
  # @param [String] absolute path to config file to edit, i.e. '/etc/gemrc'
  # @param [String, Array] Array of urls to add, deleting all others
  def self.config_sources(config_file, sources_to_add)
    unless ::File.directory?(::File.dirname(config_file))
      FileUtils.mkdir_p(::File.dirname(config_file))
    end
    sources = Gems.src_cmd(config_file, "--list").split("\n")
    # Discard the message (starting with ***) and empty lines returned by gem sources
    sources.reject! { |s| s =~ /^\*\*\*/ || s.chomp == "" } 

    sources_to_delete = sources - sources_to_add
    sources_to_add.each do |m|
      begin
        unless sources.include?(m)
          puts "Adding gem source: #{m}"
          Gems.src_cmd(config_file, "--add #{m}")
        end
      rescue Exception => e
        puts "Error Adding gem source #{m}: #{e}\n...continuing with others..."
      end
    end

    sources_to_delete.each do |m|
      begin
        puts "Removing stale gem source: #{m}"
        Gems.src_cmd(config_file, "--remove #{m}")
      rescue Exception => e
        puts "Error Adding gem source #{m}: #{e}\n...continuing with others..."
      end
    end
  end

  module RubyGems
    # The different generate classes will always generate an exception ("string") if there's anything that went wrong. If no exception, things went well.
    def self.generate(description, base_urls, frozen_date="latest")

      repo_path = "archive/"+ (frozen_date || "latest")
      mirror_list = base_urls.map do |bu|
        bu +='/' unless bu[-1..-1] == '/' # ensure the base url is terminated with a '/'
        bu+repo_path+ ( repo_path[-1..-1] == '/'? "":"/")
      end

      # Setup rubygems sources for both sandbox and system ruby, even if system
      # ruby is not installed. The config file doesn't conflict with package
      # managers, so can be added safely and will be picked up if a user
      # installs the rubygems package
      sandbox_dir = ::RightScale::Platform.filesystem.sandbox_dir
      Gems.config_sources("/etc/gemrc", mirror_list)
      Gems.config_sources("#{sandbox_dir}/etc/gemrc", mirror_list)
      mirror_list
    end
  end # Module RubyGems

end

# Examples of usage...
#Gems::RubyGems.generate("RubyGems description", ["http://a.com/rubygems","http://b.com/rubygems"], "20081010")
