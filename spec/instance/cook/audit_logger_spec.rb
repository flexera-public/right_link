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
#
require File.join(File.dirname(__FILE__), 'spec_helper')
require 'right_agent/log'
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'cook', 'audit_stub'))

describe RightScale::AuditLogger do

  before(:each) do
    @auditor = flexmock(RightScale::AuditStub.instance)
    @logger = RightScale::AuditLogger.new
    @logger.level = Logger::DEBUG
  end

  it 'should append info text' do
    @auditor.should_receive(:append_output).times(3)
    @logger.info
    @logger.warn
    @logger.unknown
  end

  it 'should log debug text' do
    flexmock(RightScale::Log).should_receive(:debug).once
    @logger.debug
  end

  it 'should append error text' do
    @auditor.should_receive(:append_error).twice
    @logger.error
    @logger.fatal
  end

  execution_errors = {
    'RightScriptProvider (Linux)' => [
      "RightScript[TonyS Always Fail] (/var/cache/rightscale/right_scripts/default/right_scripts_cookbook/recipes/TonyS_Always_Fail.rb:1:in `from_file') had an error:\n" +
      "RightScript[TonyS Always Fail] (right_scripts_cookbook::TonyS_Always_Fail line 1) had an error: RightScale::Exceptions::Exec: RightScript < TonyS Always Fail > exited with 42\n" +
      "/opt/rightscale/right_link/lib/chef/providers/right_script_provider.rb:137:in `action_run'",
      "RightScript[TonyS Always Fail] (right_scripts_cookbook::TonyS_Always_Fail line 1) had an error: RightScale::Exceptions::Exec: RightScript < TonyS Always Fail > exited with 42"
    ],
    #TODO capture an actual Windows RightScript failure and put it here instead
    'RightScriptProvider (Windows)' => [
      "RightScript[TonyS Always Fail] (/var/cache/rightscale/right_scripts/default/right_scripts_cookbook/recipes/TonyS_Always_Fail.rb:1:in `from_file') had an error:\n" +
      "RightScript[TonyS Always Fail] (right_scripts_cookbook::TonyS_Always_Fail line 1) had an error: RightScale::Exceptions::Exec: RightScript < TonyS Always Fail > exited with 42\n" +
      "/opt/rightscale/right_link/lib/chef/providers/right_script_provider.rb:137:in `action_run'",
      "RightScript[TonyS Always Fail] (right_scripts_cookbook::TonyS_Always_Fail line 1) had an error: RightScale::Exceptions::Exec: RightScript < TonyS Always Fail > exited with 42"
    ],
    #TODO capture an actual PowershellProvider failure and put it here instead!
    'PowershellProvider'  => [
      "db_sqlserver_database[app_test] (C:/PROGRA~1/RIGHTS~1/SandBox/Ruby/lib/ruby/gems/1.8/gems/chef-0.8.16.3/lib/chef/mixin/recipe_definition_dsl_core.rb line 59) had an error:\nUnexpected exit code from action. Expected 0 but returned 1.  Script: C:/DOCUME~1/ALLUSE~1/APPLIC~1/RIGHTS~1/cache/RIGHTS~1/COOKBO~1/3222BD~1/repo/COOKBO~1/DB_SQL~1/POWERS~1/database/run_command.ps1\n" +
      "RightScript[TonyS Always Fail] (right_scripts_cookbook::TonyS_Always_Fail line 1) had an error: RightScale::Exceptions::Exec: RightScript < TonyS Always Fail > exited with 42\n"+
      "/opt/rightscale/right_link/lib/chef/providers/right_script_provider.rb:137:in `action_run'",
      "An external command returned an error during the execution of Chef:\n\nUnexpected exit code from action. Expected 0 but returned 1.  Script: C:/DOCUME~1/ALLUSE~1/APPLIC~1/RIGHTS~1/cache/RIGHTS~1/COOKBO~1/3222BD~1/repo/COOKBO~1/DB_SQL~1/POWERS~1/database/run_command.ps1"
    ],
  }

  execution_errors.each_pair do |source, errors|
    it "should filter script execution errors logged by #{source}" do
      @auditor.should_receive(:append_error).once

      chef_message = errors.first
      executable_sequence_message = errors.last

      @logger.error(chef_message)  # Chef attempts to log but is filtered
      @logger.error(executable_sequence_message)  # executable_sequence is not filtered
    end
  end

end
