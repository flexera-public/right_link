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

# Load files required by then runner process
# This process is responsible for running Chef
# It's a short lived process that runs one Chef converge then dies
# It talks back to the RightLink agent using the command protocol

COOK_BASE_DIR = File.join(File.dirname(__FILE__), 'cook')

require File.normalize_path(File.join(COOK_BASE_DIR, 'cook.rb'))
require File.normalize_path(File.join(COOK_BASE_DIR, 'agent_connection.rb'))
require File.normalize_path(File.join(COOK_BASE_DIR, 'audit_stub.rb'))
require File.normalize_path(File.join(COOK_BASE_DIR, 'cook_state.rb'))
require File.normalize_path(File.join(COOK_BASE_DIR, 'chef_state.rb'))
require File.normalize_path(File.join(COOK_BASE_DIR, 'external_parameter_gatherer'))
require File.normalize_path(File.join(COOK_BASE_DIR, 'cookbook_path_mapping.rb'))
require File.normalize_path(File.join(COOK_BASE_DIR, 'cookbook_repo_retriever.rb'))
require File.normalize_path(File.join(COOK_BASE_DIR, 'executable_sequence.rb'))
require File.normalize_path(File.join(COOK_BASE_DIR, 'repose_downloader.rb'))
require File.normalize_path(File.join(COOK_BASE_DIR, 'shutdown_request_proxy.rb'))
require File.normalize_path(File.join(COOK_BASE_DIR, 'proxy_repose_downloader.rb'))
