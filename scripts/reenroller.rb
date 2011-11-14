# === Synopsis:
#   RightScale Re-enroller (rs_reenroll) - (c) 2010-2011 RightScale Inc
#
#   Re-enroller causes the instance to re-enroll
#   CAUTION: This process may take a while to take place, during that time
#            the agent will be un-responsive. Only use when the instance is in
#            a bad state and you understand the consequences.
#
# === Usage
#    rs_reenroll
#
#    Options:
#      --verbose, -v     Display debug information
#      --help:           Display help
#

require 'rubygems'
require 'optparse'
require 'fileutils'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'

require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'agent_config'))

module RightScale

  class Reenroller

    if RightScale::Platform.windows?
      # Note we currently only need a reenroller state file under windows.
      STATE_DIR  = AgentConfig.agent_state_dir
      STATE_FILE = File.join(STATE_DIR, 'reenroller_state.js')
    end

    # Trigger re-enrollment
    #
    # === Return
    # true:: Always return true
    def run(options)
      AgentConfig.root_dir = RightScale::Platform.filesystem.right_link_dir
      if RightScale::Platform.windows?
        cleanup_certificates(options)
        # Write state file to indicate to RightScaleService that it should not
        # enter the rebooting state (which is the default behavior when the
        # RightScaleService starts).
        reenroller_state = {:reenroll => true}
        File.open(STATE_FILE, "w") { |f| f.write reenroller_state.to_json }
        print 'Restarting RightScale service...' if options[:verbose]
        res = system('net start RightScale')
        puts to_ok(res) if options[:verbose]
      else
        print 'Stopping RightLink daemon...' if options[:verbose]
        pid_file = AgentConfig.pid_file('instance')
        pid = pid_file ? pid_file.read_pid[:pid] : nil
        system('/opt/rightscale/sandbox/bin/monit -c /opt/rightscale/etc/monitrc stop checker')
        system('/opt/rightscale/sandbox/bin/monit -c /opt/rightscale/etc/monitrc stop instance')
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
          res = Process.kill('KILL', pid) rescue nil
          puts to_ok(res) if options[:verbose]
        end
        # Now stop monit so it doesn't get in the way
        system('/opt/rightscale/sandbox/bin/monit -c /opt/rightscale/etc/monitrc quit')
        pid_file = '/opt/rightscale/var/run/monit.pid'
        pid = File.exist?(pid_file) ? IO.read(pid_file).to_i : nil
        while pid && process_running?(pid) do
          puts 'Waiting for monit to exit...' if options[:verbose]
          sleep(1)
        end
        cleanup_certificates(options)

        # Resume option bypasses cloud state initialization so that we can
        # override the user data
        puts((options[:resume] ? 'Resuming' : 'Restarting') + ' RightLink daemon...') if options[:verbose]
        action = (options[:resume] ? 'resume' : 'start')
        res = system("/etc/init.d/rightlink #{action} > /dev/null")
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

       opts.on('-r', '--resume') do
          options[:resume] = true
        end

       opts.on('-v', '--verbose') do
          options[:verbose] = true
        end

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

    # Map given value to [OK] or [ERROR]
    # By default return [OK] unless value is false or nil
    # Override default behavior by using 'ok_values' and/or 'error_values'
    #
    # === Parameters
    # val(Object):: Value to be tested
    # default_ok(Boolean):: Whether default value is '[OK]' (true) or '[ERROR]' (false), '[OK]' by default
    # ok_values(Array):: Array of values that will cause +to_ok+ to return '[OK]' if defined, nil by default
    # error_values(Array):: Array of values that will cause +to_ok+ to return '[ERROR]' if defined, [nil, false] by default
    #
    # === Return
    # status(String):: [OK] or [ERROR]
    def to_ok(val, default_value='[OK]', ok_values=nil, error_values=[nil, false])
      return '[OK]' if ok_values && ok_values.include?(val)
      return '[ERROR]' if error_values && error_values.include?(val)
      return default_value
    end

    # Cleanup certificates
    #
    # === Parameters
    # options(Hash):: Options hash
    #
    # === Return
    # true:: Always return true
    def cleanup_certificates(options)
      puts 'Cleaning up certificates...' if options[:verbose]
      AgentConfig.certs_files("*.{cert,key}").each { |f| FileUtils.rm_f(f) } # requires that root_dir already known in AgentConfig
    end

    # Checks whether process with given pid is running
    #
    # === Parameters
    # pid(Fixnum):: Process id to be checked
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

  end # Reenroller

end # RightScale

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
