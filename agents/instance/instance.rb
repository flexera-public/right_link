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

# Instance agent initialization

# Path to file containing code dynamically generated before RightLink agent
# started. Its content will get evaled in the context of the agent.
RIGHT_LINK_ENV = File.join(File.dirname(__FILE__), 'right_link_env.rb')

BASE_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
require File.join(BASE_DIR, 'agents', 'lib', 'instance')
require File.join(BASE_DIR, 'chef', 'lib', 'providers')
require File.join(BASE_DIR, 'chef', 'lib', 'plugins')
require File.join(BASE_DIR, 'command_protocol', 'lib', 'command_protocol')
require File.join(BASE_DIR, 'payload_types', 'lib', 'payload_types')
require File.join(BASE_DIR, 'repo_conf_generators', 'lib', 'repo_conf_generators')
require 'right_popen'

RightScale::SecureSerializerInitializer.init(@options[:agent] || 'instance', @identity, RightScale::RightLinkConfig[:certs_dir])

#Initialize any singletons that have dependencies on non-singletons
RightScale::AgentTagsManager.instance.agent = self

register setup = InstanceSetup.new(@options[:identity])
register scheduler = InstanceScheduler.new(self)
register AgentManager.new(self)
register InstanceServices.new(@identity)

# Start command runner to enable running RightScripts and recipes from the command line
cmd_opts = RightScale::CommandRunner.start(RightScale::CommandConstants::BASE_INSTANCE_AGENT_SOCKET_PORT,
                                           @identity,
                                           InstanceCommands.get(@identity, scheduler),
                                           @options)

# Set environment variable containing options so child (cook) process can retrieve them
RightScale::OptionsBag.store(@options.merge(cmd_opts))

# Load environment code if present
# The file 'right_link_env.rb' should be generated before the RightLink
# agent is started. It can contain code generated dynamically e.g. from
# the cloud user data
instance_eval(IO.read(RIGHT_LINK_ENV)) if File.file?(RIGHT_LINK_ENV)

# Hook up instance setup actor so it gets called back whenever the AMQP
# connection fails
@broker.connection_status { |status| setup.connection_status(status) }
