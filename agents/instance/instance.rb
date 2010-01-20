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
require File.join(BASE_DIR, 'agents', 'lib', 'instance_lib')
require File.join(BASE_DIR, 'chef', 'lib', 'providers')
require File.join(BASE_DIR, 'chef', 'lib', 'plugins')
require File.join(BASE_DIR, 'command_protocol', 'lib', 'command_protocol')
require File.join(BASE_DIR, 'payload_types', 'lib', 'payload_types')
require File.join(BASE_DIR, 'repo_conf_generators', 'lib', 'repo_conf_generators')
require File.join(BASE_DIR, 'right_popen', 'lib', 'right_popen')
require 'right_popen'  # now an installed gem

RightScale::SecureSerializerInitializer.init(options[:agent] || 'instance', options[:identity], RightScale::RightLinkConfig[:certs_dir])

#Initialize any singletons that have dependencies on non-singletons
RightScale::AgentTagsManager.instance.agent = self

register setup = InstanceSetup.new(options[:identity])
register scheduler = InstanceScheduler.new(self)
register AgentManager.new
register InstanceServices.new(options[:identity])

# Start command runner to enable running RightScripts and recipes from the command line
RightScale::CommandRunner.start(options[:identity], scheduler)

# Load environment code if present
# The file 'right_link_env.rb' should be generated before the RightLink
# agent is started. It can contain code generated dynamically e.g. from
# the cloud user data
instance_eval(IO.read(RIGHT_LINK_ENV)) if File.file?(RIGHT_LINK_ENV)

# Hook up instance setup actor so it gets called back whenever the AMQP
# connection fails
@amq.__send__(:connection).connection_status { |status| setup.connection_status(status) }
