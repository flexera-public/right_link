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

# Instance agent initialization to be executed in the RightScale::Agent context

# Path to file containing code dynamically generated before RightLink agent started
# Its content will get eval'd in the context of this agent
RIGHT_LINK_ENV = File.join(File.dirname(__FILE__), 'right_link_env.rb')

require 'right_popen'
require 'right_agent/core_payload_types'
require 'right_agent/command/agent_manager_commands'

BASE_DIR = File.join(File.dirname(__FILE__), '..', 'lib')
require File.normalize_path(BASE_DIR, 'instance')
require File.normalize_path(BASE_DIR, 'chef', 'providers')
require File.normalize_path(BASE_DIR, 'chef', 'plugins')
require File.normalize_path(BASE_DIR, 'repo_conf_generators')
¥
SecureSerializerInitializer.init('instance', @identity)

# Initialize any singletons that have dependencies on non-singletons
AgentTagsManager.instance.agent = self

register setup = InstanceSetup.new(@identity)
register scheduler = InstanceScheduler.new(self)
register agent_manager = AgentManager.new(self)
register InstanceServices.new(@identity)

# Start command runner to enable running instance agent reque¥sts from the command line
cmd_opts = CommandRunner.start(CommandConstants::BASE_INSTANCE_AGENT_SOCKET_PORT, @identity, AgentManagerCommands.get(agent_manager))

# Initialize shutdown request state
ShutdownRequest.init(scheduler)

# Set environment variable containing options so child (cook) process can retrieve them
OptionsBag.store(@options.merge(cmd_opts))

# Load environment code if present
# The file 'right_link_env.rb' should be generated before the RightLink agent is started
# It can contain code generated dynamically e.g. from the cloud user data
instance_eval(IO.read(RIGHT_LINK_ENV)) if File.file?(RIGHT_LINK_ENV)

# Hook up instance setup actor so it gets called back whenever the AMQP connection fails
@broker.connection_status { |status| setup.connection_status(status) }
