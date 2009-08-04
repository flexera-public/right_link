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

BASE_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
require File.join(BASE_DIR, 'agents', 'lib', 'instance_lib')
require File.join(BASE_DIR, 'lib', 'command_protocol', 'lib', 'command_protocol')
require File.join(BASE_DIR, 'lib', 'payload_types', 'lib', 'payload_types')
require File.join(BASE_DIR, 'lib', 'repo_conf_generators', 'lib', 'repo_conf_generators')
require File.join(BASE_DIR, 'lib', 'right_popen', 'lib', 'right_popen')

RightScale::SecureSerializerInitializer.init('instance', options[:identity], RightScale::RightLinkConfig[:certs_dir])
register InstanceSetup.new(options[:identity])
register InstanceScheduler.new(options[:identity])
register AgentManager.new

# Start command runner to enable running RightScripts and recipes from the command line
RightScale::CommandRunner.start(options[:identity])
