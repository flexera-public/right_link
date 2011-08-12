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

INSTANCE_BASE_DIR = File.join(File.dirname(__FILE__), 'instance')

require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'agent_config'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'audit_cook_stub'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'audit_logger'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'audit_proxy'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'bundles_queue'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'cook', 'cook_state'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'downloader'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'duplicable'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'exceptions'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'executable_sequence_proxy'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'instance_commands'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'instance_state'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'login_manager'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'operation_context'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'options_bag'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'payload_formatter'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'reenroll_manager'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'right_scripts_cookbook'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'shutdown_request'))
require File.normalize_path(File.join(INSTANCE_BASE_DIR, 'volume_management'))
