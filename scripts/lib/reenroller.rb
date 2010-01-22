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

$:.push(File.dirname(__FILE__))

require 'optparse'
require 'command_client'
require 'fileutils'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'right_link_config'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'platform'))
require File.join(File.dirname(__FILE__), 'agent_utils')

module RightScale

  class Reenroller

    include Utils

    VERSION = [0, 1]

    # Trigger re-enrollment
    #
    # === Return
    # true:: Always return true
    def run(options)
      if Platform.windows?
        print 'Stopping RightLink service...' if options[:verbose]
        res = system('net stop RSRightLink')
        puts to_ok(res) if options[:verbose]
        cleanup_certificates(options)
        print 'Restarting RightLink service...' if options[:verbose]
        res = system('net start RSRightLink')
        puts to_ok(res) if options[:verbose]
      else
        print 'Stopping RightLink daemon...' if options[:verbose]
        pid_file = agent_pid_file('instance')
        pid = pid_file.read_pid if pid_file
        system('monit stop instance')
        # Wait for agent process to terminate
        retries = 0
        while process_running?(pid) && retries < 20
          sleep(0.5)
          retries += 1
          print '.' if options[:verbose]
        end
        puts to_ok(!process_running?(pid)) if options[:verbose]
        # Kill it if it's still alive after ~ 10 sec
        if process_running?(pid)
          print 'Forcing RightLink daemon to exit...' if options[:verbose]
          res = Process.kill(KILL, pid) rescue nil
          puts to_ok(res) if options[:verbose]
        end
        cleanup_certificates(options)
        puts 'Restarting RightLink daemon...' if options[:verbose]
        res = system('/etc/init.d/rightlink start > /dev/null')
      end
      true
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options<Hash>:: Hash of options as defined by the command line
    def parse_args
      options = { :verbose => false }

      opts = OptionParser.new do |opts|

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

      opts.parse!(ARGV)
      options
    end

    protected

    # Map given value to [OK] or [ERROR]
    # By default return [OK] unless value is false or nil
    # Override default behavior by using 'ok_values' and/or 'error_values'
    #
    # === Parameters
    # val<Object>:: Value to be tested
    # default_ok<TrueClass|FalseClass>:: Whether default value is '[OK]' (true) or '[ERROR]' (false), '[OK]' by default
    # ok_values<Array>:: Array of values that will cause +to_ok+ to return '[OK]' if defined, nil by default
    # error_values<Array>:: Array of values that will cause +to_ok+ to return '[ERROR]' if defined, [nil, false] by default
    #
    # === Return
    # status<String>:: [OK] or [ERROR]
    def to_ok(val, default_value='[OK]', ok_values=nil, error_values=[nil, false])
      return '[OK]' if ok_values && ok_values.include?(val)
      return '[ERROR]' if error_values && error_values.include?(val)
      return default_value
    end

    # Cleanup certificates
    #
    # === Parameters
    # options<Hash>:: Options hash
    #
    # === Return
    # true:: Always return true
    def cleanup_certificates(options)
      puts 'Cleaning up certificates...' if options[:verbose]
      FileUtils.rm_rf(certs_dir) if File.exist?(certs_dir)
      FileUtils.mkdir_p(certs_dir)
    end

    # Checks whether process with given pid is running
    #
    # === Parameters
    # pid<Fixnum>:: Process id to be checked
    #
    # === Return
    # true:: If process is running
    # false:: Otherwise
    def process_running?(pid)
      return false unless pid
      Process.getpgid(pid) != -1
    rescue Errno::ESRCH
      false
    end

    # Version information
    #
    # === Return
    # ver<String>:: Version information
    def version
      ver = "rs_reenroll #{VERSION.join('.')} - RightLink reenroller (c) 2009 RightScale"
    end

  end
end
