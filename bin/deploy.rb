#!/opt/rightscale/sandbox/bin/ruby

# Copyright (c) 2009-2011 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.
#

# Standard library dependencies
require 'uri'
require 'fileutils'

# Gem dependencies
require 'rubygems'
require 'right_agent'

# RightLink dependencies
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'instance_state'))

module RightScale

  class AgentDeployerRunner

    def self.run
      client = AgentDeployerRunner.new
      Kernel.exit client.deploy
    end

    def deploy
      configure_logging
      read_userdata
      cleanup_old_state
      invoke_rad
    end

    protected

    def configure_logging
      Log.program_name = 'RightLink'
      Log.log_to_file_only(false)
      Log.level = Logger::INFO
      FileUtils.mkdir_p(File.dirname(InstanceState::BOOT_LOG_FILE))
      Log.add_logger(Logger.new(File.open(InstanceState::BOOT_LOG_FILE, 'a')))
      Log.add_logger(Logger.new(STDOUT))
    end

    def read_userdata
      dir  = AgentConfig.cloud_state_dir
      file = File.join(dir, 'user-data.rb')
      load file
    end

    def cleanup_old_state
      # On Linux systems, we need to nuke monit config files generated for
      # old instance agents. On Windows this is a no-op (the dir glob
      # returns an empty list).
      old_monit_conf = Dir['/opt/rightscale/etc/monit.d/*.conf']
      old_monit_conf.each { |file| File.unlink(file) }
    end

    def invoke_rad
      # Form RabbitMQ broker host:id list from RS_RN_URL and RS_RN_HOST
      url = URI.parse(ENV['RS_RN_URL'])
      host = ENV['RS_RN_HOST']
      if !host
        host = url.host
      elsif host[0,1] == ':' || host[0,1] == ','
        host = "#{url.host}#{host}"
      end

      cmd_opts = [ 'instance',
                   '-i', ENV['RS_RN_ID'],
                   '-t', ENV['RS_RN_AUTH'],
                   '-h', host,
                   '-u', url.user,
                   '-p', url.password,
                   '-v', url.path,
                   '-S' ]

      if ENV['http_proxy']
        cmd_opts << ['--http-proxy', ENV['http_proxy']]
      end

      if ENV['no_proxy']
        cmd_opts << ['--http-no-proxy', ENV['no_proxy']]
      end

      if Platform.linux?
        FileUtils.mkdir_p('/opt/rightscale/etc/monit.d')
        cmd_opts << '--monit'
        cmd_opts << '--agent-checker'
      end

      cmd = Platform.shell.format_executable_command(File.join(Platform.filesystem.private_bin_dir, 'rad'), cmd_opts)

      Log.info("Deploying agent with command: #{cmd}")
      exec(cmd)
    end

  end

end

# The $0 argument is -e in windows because of how we wrap the call to get live
# console output. we don't need to worry about symlinks in Windows, so always
# run the deployer on that platform
RightScale::AgentDeployerRunner.run if (__FILE__ == $0 || RightScale::Platform.windows?)
