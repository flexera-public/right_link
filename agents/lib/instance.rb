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

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'right_link_config'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common'))
require File.join(File.dirname(__FILE__), 'instance', 'audit_logger')
require File.join(File.dirname(__FILE__), 'instance', 'auditor_proxy')
require File.join(File.dirname(__FILE__), 'instance', 'chef_state')
require File.join(File.dirname(__FILE__), 'instance', 'dev_state')
require File.join(File.dirname(__FILE__), 'instance', 'downloader')
require File.join(File.dirname(__FILE__), 'instance', 'duplicable')
require File.join(File.dirname(__FILE__), 'instance', 'executable_sequence')
require File.join(File.dirname(__FILE__), 'instance', 'instance_commands')
require File.join(File.dirname(__FILE__), 'instance', 'instance_configuration')
require File.join(File.dirname(__FILE__), 'instance', 'instance_state')
require File.join(File.dirname(__FILE__), 'instance', 'login_manager')
require File.join(File.dirname(__FILE__), 'instance', 'request_forwarder')
require File.join(File.dirname(__FILE__), 'instance', 'right_scripts_cookbook')
require File.join(File.dirname(__FILE__), 'instance', 'user_data_writer')
