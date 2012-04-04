# === Synopsis:
#   RightScale Log Level Manager (rs_log_level) - (c) 2009-2011 RightScale Inc
#
#   Log level manager allows setting and retrieving the RightLink agent
#   log level.
#
# === Examples:
#   Retrieve log level:
#     rs_log_level
#
#   Set log level to debug:
#     rs_log_level --log-level debug
#     rs_log_level -l debug
#
# === Usage
#    rs_set_log_level [--log-level, -l debug|info|warn|error|fatal]
#
#    Options:
#      --log-level, -l LVL  Set log level of RightLink agent
#      --verbose, -v        Display debug information
#      --help:              Display help
#      --version:           Display version information
#
#    No options prints the current RightLink agent log level
#

require 'right_agent/scripts/log_level_manager'

module RightScale

  class RightLinkLogLevelManager < LogLevelManager

    # Convenience wrapper for creating and running log level manager
    #
    # === Return
    # true:: Always return true
    def self.run
      m = RightLinkLogLevelManager.new
      m.manage(m.parse_args)
    rescue Errno::EACCES => e
      STDERR.puts e.message
      STDERR.puts "Try elevating privilege (sudo/runas) before invoking this command."
      exit(2)
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args
      options = { :agent_name => 'instance', :verbose => false }

      opts = OptionParser.new do |opts|

        opts.on('-l', '--log-level LEVEL') do |l|
          fail("Invalid log level '#{l}'") unless AgentManager::LEVELS.include?(l.to_sym)
          options[:level] = l
        end

        opts.on('-v', '--verbose') do
          options[:verbose] = true
        end

      end

      opts.on_tail('--version') do
        puts version
        succeed
      end
      
      opts.on_tail('--help') do
         puts Usage.scan(__FILE__)
         exit
      end

      begin
        opts.parse!(ARGV)
      rescue Exception => e
        puts e.message + "\nUse --help for additional information"
        exit(1)
      end
      options
    end
    
protected

    # Version information
    #
    # === Return
    # (String):: Version information
    def version
      gemspec = eval(File.read(File.join(File.dirname(__FILE__), '..', 'right_link.gemspec')))
      "rs_log_level #{gemspec.version} - RightLink's log level (c) 2011 RightScale"
    end

  end
end

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
