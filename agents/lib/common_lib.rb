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

require File.expand_path(File.join(__FILE__, '..', '..', '..', 'config', 'right_link_config'))
require File.join(File.dirname(__FILE__), 'common', 'agent_identity')
require File.join(File.dirname(__FILE__), 'common', 'audit_formatter')
require File.join(File.dirname(__FILE__), 'common', 'exceptions')
require File.join(File.dirname(__FILE__), 'common', 'right_link_log')
require File.join(File.dirname(__FILE__), 'common', 'multiplexer')
require File.join(File.dirname(__FILE__), 'common', 'secure_serializer_initializer')
require File.join(File.dirname(__FILE__), 'common', 'right_link_tracer')
