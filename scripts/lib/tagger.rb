# === Synopsis:
#   RightScale Tagger (rs_tag)
#   (c) 2010 RightScale
#
#   Tagger allows querying, adding and removing tags on the current instance
#
# === Examples:
#   Retrieve all tags:
#     rs_tag --list
#     rs_tag -l
#
#   Add tag 'a_tag' to instance:
#     rs_tag --add a_tag
#     rs_tag -a a_tag
#
#   Remove tag 'a_tag':
#     rs_tag --remove a_tag
#     rs_tag -r a_tag
#
# === Usage
#    rs_tag (--list, -l | --add, -a name | --remove, -r name)
#
#    Options:
#      --list, -l        List current server tags
#      --add, -a NAME    Add tag NAME
#      --remove, -r NAME Remove tag NAME
#      --verbose, -v     Display debug information
#      --help:           Display help
#      --version:        Display version information
#
$:.push(File.dirname(__FILE__))

require 'optparse'
require 'rdoc/ri/ri_paths' # For backwards compat with ruby 1.8.5
require 'rdoc/usage'
require 'rdoc_patch'
require 'command_client'
require File.join(File.dirname(__FILE__), '..', '..', 'actors', 'lib', 'agent_manager')

module RightScale

  class Tagger

    VERSION = [0, 1]

    # Manage instance tags
    #
    # === Parameters
    # options(Hash):: Hash of options as defined in +parse_args+
    #
    # === Return
    # true:: Always return true
    def run(options)
      unless options.include?(:action)
        puts "Missing argument, rs_tag --help for additional information"
        exit 1
      end
      cmd = { :name => options[:action] }
      cmd[:tag] = options[:tag] if options[:tag]
      client = CommandClient.new
      begin
        client.send_command(cmd, options[:verbose]) do |res|
          if options[:action] == :get_tags
            if res.empty?
              puts "No server tag found"
            else
              puts "Server tags (#{res.size}):\n#{res.map { |tag| "  - #{tag}" }.join("\n")}\n"
            end
          else
            puts res
          end
        end
      rescue Exception => e
        fail(e.message)
      end
      true
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args
      options = { :verbose => false }

      opts = OptionParser.new do |opts|

        opts.on('-l', '--list') do
          options[:action] = :get_tags
        end

        opts.on('-a', '--add NAME') do |n|
          options[:action] = :add_tag
          options[:tag] = n
        end

        opts.on('-r', '--remove NAME') do |n|
          options[:action] = :remove_tag
          options[:tag] = n
        end

        opts.on('-v', '--verbose') do
          options[:verbose] = true
        end

      end

      opts.on_tail('--version') do
        puts version
        exit
      end

      opts.on_tail('--help') do
         RDoc::usage_from_file(__FILE__)
         exit
      end

      begin
        opts.parse!(ARGV)
      rescue Exception => e
        puts e.message + "\nUse rs_tag --help for additional information"
      end
      options
    end

protected

    # Print error on console and exit abnormally
    #
    # === Parameter
    # msg(String):: Error message, default to nil (no message printed)
    # print_usage(Boolean):: Whether script usage should be printed, default to false
    #
    # === Return
    # R.I.P. does not return
    def fail(msg=nil, print_usage=false)
      puts "** #{msg}" if msg
      RDoc::usage_from_file(__FILE__) if print_usage
      exit(1)
    end

    # Version information
    #
    # === Return
    # ver(String):: Version information
    def version
      ver = "rs_tagger #{VERSION.join('.')} - RightLink's tagger (c) 2010 RightScale"
    end

  end
end

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
