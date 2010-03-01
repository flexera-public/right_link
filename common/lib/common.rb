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

require 'rubygems'
require 'amqp'
require 'mq'
require 'json'
require 'yaml'
require 'openssl'

require File.expand_path(File.join(__FILE__, '..', '..', '..', 'config', 'right_link_config'))
require File.join(File.dirname(__FILE__), 'common', 'eventmachine')
require File.join(File.dirname(__FILE__), 'common', 'amqp')
require File.join(File.dirname(__FILE__), 'common', 'util')
require File.join(File.dirname(__FILE__), 'common', 'config')
require File.join(File.dirname(__FILE__), 'common', 'packets')
require File.join(File.dirname(__FILE__), 'common', 'console')
require File.join(File.dirname(__FILE__), 'common', 'daemonize')
require File.join(File.dirname(__FILE__), 'common', 'pid_file')
require File.join(File.dirname(__FILE__), 'common', 'exceptions')
require File.join(File.dirname(__FILE__), 'common', 'right_link_log')
require File.join(File.dirname(__FILE__), 'common', 'multiplexer')
require File.join(File.dirname(__FILE__), 'common', 'right_link_tracer')
require File.join(File.dirname(__FILE__), 'common', 'audit_formatter')
require File.join(File.dirname(__FILE__), 'common', 'serializer')
require File.join(File.dirname(__FILE__), 'common', 'agent', 'agent_identity')
require File.join(File.dirname(__FILE__), 'common', 'agent', 'actor')
require File.join(File.dirname(__FILE__), 'common', 'agent', 'actor_registry')
require File.join(File.dirname(__FILE__), 'common', 'agent', 'dispatcher')
require File.join(File.dirname(__FILE__), 'common', 'agent', 'agent')
require File.join(File.dirname(__FILE__), 'common', 'agent', 'mapper_proxy')
require File.join(File.dirname(__FILE__), 'common', 'agent', 'secure_serializer_initializer')
require File.join(File.dirname(__FILE__), 'common', 'agent', 'agent_tags_manager')
require File.join(File.dirname(__FILE__), 'common', 'security', 'cached_certificate_store_proxy')
require File.join(File.dirname(__FILE__), 'common', 'security', 'certificate')
require File.join(File.dirname(__FILE__), 'common', 'security', 'certificate_cache')
require File.join(File.dirname(__FILE__), 'common', 'security', 'distinguished_name')
require File.join(File.dirname(__FILE__), 'common', 'security', 'encrypted_document')
require File.join(File.dirname(__FILE__), 'common', 'security', 'rsa_key_pair')
require File.join(File.dirname(__FILE__), 'common', 'security', 'secure_serializer')
require File.join(File.dirname(__FILE__), 'common', 'security', 'signature')
require File.join(File.dirname(__FILE__), 'common', 'security', 'static_certificate_store')
