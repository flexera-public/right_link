# === Synopsis:
#   RightScale Cloud Controller (cloud) - Copyright (c) 2011 by RightScale Inc
#
#   cloud is a command line tool which invokes cloud-specific actions
#
# === Examples:
#   Write cloud and user metadata to cache directory using default cloud:
#     cloud --action=write_metadata
#
#   Write user metadata only to cache directory using named ec2 cloud:
#     cloud --name=ec2 --action=write_user_metadata
#
#   Read default cloud user metadata in dictionary format (metadata is output):
#     cloud --action=read_user_metadata
#                      --parameters=dictionary_metadata_writer
#
# === Usage:
#    cloud [options]
#
#    options:
#      --action, -a       Action to perform (required, see below for details).
#      --name, -n         Cloud to use instead of attempting to determine a
#                         default cloud.
#      --parameters, -p   Parameters passed to cloud action as either a single
#                         string argument or as a square-bracketed array in
#                         JSON format for multiple arguments.
#      --only-if, -o      Ignores unknown cloud actions instead of printing an
#                         error.

require 'rubygems'
require 'json'
require 'logger'
require 'optparse'
require 'fileutils'
require 'right_agent'
require 'right_agent/scripts/usage'

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'agent_config'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'clouds', 'register_clouds'))

module RightScale

  class CloudController

    # Convenience wrapper
    def self.run
      controller = CloudController.new
      controller.control(controller.parse_args)
    end

    # Undecorated formatter to support legacy console output
    class PlainLoggerFormatter < Logger::Formatter
      def call(severity, time, program_name, message)
        return message + "\n"
      end
    end

    # Parse arguments and run
    def control(options)

      fail("No action specified on the command line.") unless options[:action]
      action = options[:action].to_sym
      name = options[:name]
      parameters = options[:parameters] || []
      only_if = options[:only_if] || false

      cloud = CloudFactory.instance.create(name, :logger => default_logger)
      if cloud.respond_to?(action)
        # Expect most methods to return ActionResult, but a cloud can expose any
        # custom method so we can't assume return type
        result = cloud.send(action, *parameters)
        $stderr.puts result.error if result.respond_to?(:error) && result.error
        $stdout.puts result.output if result.respond_to?(:output) && result.output
        exit result.exitstatus if result.respond_to?(:exitstatus)
        exit 0
      elsif only_if
        exit 0  # ignore missing method by request.
      else
        $stderr.puts "ERROR: Unknown cloud action: #{action}"
        exit 1
      end
    rescue SystemExit
      raise
    rescue Exception => e
      $stderr.puts "ERROR: #{e.message}"
      exit 1
    end

    # Parse arguments
    def parse_args
      options = {:name => CloudFactory::UNKNOWN_CLOUD_NAME}
      opts = OptionParser.new do |opts|

        opts.on("-a", "--action ACTION") do |action|
          options[:action] = action
        end

        opts.on("-n", "--name NAME") do |name|
          options[:name] = name
        end

        opts.on("-o", "--only-if") do
          options[:only_if] = true
        end

        opts.on("-p", "--parameters PARAMETERS") do |parameters|
          if parameters.start_with?('[')
            parameters = JSON.parse(parameters)
          else
            parameters = [parameters]
          end
          options[:parameters] = parameters
        end

        opts.on("--help") do
          puts Usage.scan(__FILE__)
          exit 0
        end

      end

      opts.parse(ARGV)
      options
    end

    # Default logger for printing to console
    def default_logger
      logger = Logger.new(STDOUT)
      logger.level = Logger::INFO
      logger.formatter = PlainLoggerFormatter.new
      return logger
    end

  end # CloudController

end # RightScale

#
# Copyright (c) 2011 RightScale Inc
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
