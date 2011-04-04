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

require 'rubygems'
require 'amqp'
require 'mq'
require 'json'
require 'yaml'
require 'openssl'

COMMON_BASE_DIR = File.normalize_path(File.join(File.dirname(__FILE__), 'common'))
require File.join(COMMON_BASE_DIR, 'amqp')
require File.join(COMMON_BASE_DIR, 'util')
require File.join(COMMON_BASE_DIR, 'config')
require File.join(COMMON_BASE_DIR, 'packets')
require File.join(COMMON_BASE_DIR, 'payload_formatter')
require File.join(COMMON_BASE_DIR, 'console')
require File.join(COMMON_BASE_DIR, 'daemonize')
require File.join(COMMON_BASE_DIR, 'pid_file')
require File.join(COMMON_BASE_DIR, 'exceptions')
require File.join(COMMON_BASE_DIR, 'multiplexer')
require File.join(COMMON_BASE_DIR, 'right_link_log')
require File.join(COMMON_BASE_DIR, 'right_link_tracer')
require File.join(COMMON_BASE_DIR, 'audit_formatter')
require File.join(COMMON_BASE_DIR, 'serializer')
require File.join(COMMON_BASE_DIR, 'serializable')
require File.join(COMMON_BASE_DIR, 'operation_result')
require File.join(COMMON_BASE_DIR, 'subprocess')
require File.join(COMMON_BASE_DIR, 'stats_helper')
require File.join(COMMON_BASE_DIR, 'broker_client')
require File.join(COMMON_BASE_DIR, 'ha_broker_client')
require File.join(COMMON_BASE_DIR, 'agent', 'agent_identity')
require File.join(COMMON_BASE_DIR, 'agent', 'actor')
require File.join(COMMON_BASE_DIR, 'agent', 'actor_registry')
require File.join(COMMON_BASE_DIR, 'agent', 'dispatcher')
require File.join(COMMON_BASE_DIR, 'agent', 'mapper_proxy')
require File.join(COMMON_BASE_DIR, 'agent', 'agent')
require File.join(COMMON_BASE_DIR, 'agent', 'reenroll_manager')
require File.join(COMMON_BASE_DIR, 'agent', 'secure_identity')
require File.join(COMMON_BASE_DIR, 'agent', 'secure_serializer_initializer')
require File.join(COMMON_BASE_DIR, 'agent', 'agent_tags_manager')
require File.join(COMMON_BASE_DIR, 'agent', 'volume_management')
require File.join(COMMON_BASE_DIR, 'security', 'cached_certificate_store_proxy')
require File.join(COMMON_BASE_DIR, 'security', 'certificate')
require File.join(COMMON_BASE_DIR, 'security', 'certificate_cache')
require File.join(COMMON_BASE_DIR, 'security', 'distinguished_name')
require File.join(COMMON_BASE_DIR, 'security', 'encrypted_document')
require File.join(COMMON_BASE_DIR, 'security', 'rsa_key_pair')
require File.join(COMMON_BASE_DIR, 'security', 'secure_serializer')
require File.join(COMMON_BASE_DIR, 'security', 'signature')
require File.join(COMMON_BASE_DIR, 'security', 'static_certificate_store')
