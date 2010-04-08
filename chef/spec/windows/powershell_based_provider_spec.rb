#
# Copyright (c) 2010 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

# FIX: rake spec should check parent directory name?
if RightScale::RightLinkConfig[:platform].windows?
  
  require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'mock_auditor_proxy'))
  require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'chef_runner'))
  
  module PowershellBasedProviderSpec
    TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "powershell-based-provider-spec-8f3dd90c-b3f3-40d3-bf48-66508b9348b7"))
    TEST_COOKBOOK_PATH = File.normalize_path(File.dirname(__FILE__))
  end
  
  describe "given a cookbook containing a powershell provider" do

    before(:each) do
      @original_logger = ::Chef::Log.logger
      @log_file_name = File.normalize_path(File.join(Dir.tmpdir, "chef_runner_#{File.basename(__FILE__, '.rb')}_#{Time.now.strftime("%Y-%m-%d-%H%M%S")}.log"))
      @log_file = File.open(@log_file_name, 'w')

      # redirect the Chef logs to a file before creating the chef client
      ::Chef::Log.logger = Logger.new(@log_file)

      @logs = ""
      flexmock(Chef::Log).should_receive(:info).and_return { |m| @logs << m }
      flexmock(Chef::Log).should_receive(:level).and_return(Logger::DEBUG)

      mock_instance_state = flexmock('MockInstanceState', :past_scripts => [], :record_script_execution => true)
      flexmock(Chef::Provider::Powershell).new_instances.should_receive(:instance_state).and_return(mock_instance_state)

      #@debug_logs = ""
      #flexmock(Chef::Log).should_receive(:debug).and_return { |m| @debug_logs << m }
    end

    after(:each) do
      # reset the original logger and delete the log file for this run unless explicitly kept
      ::Chef::Log.logger = @original_logger
      @log_file.close rescue nil
      FileUtils.rm_f(@log_file_name) unless ENV['RS_LOG_KEEP']
    end


    it "should run a simple recipe" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_simple_recipe')
      }
      runner.call.should == true

      # TODO: verify order of execution
      (@logs =~ /\/simple_encode\/_init.ps1/).should_not be_nil
      (@logs =~ /init simple encode/).should_not be_nil

      (@logs =~ /\/simple_encode\/url_encode.ps1/).should_not be_nil
      (@logs =~ /string\+to\+encode/).should_not be_nil

      (@logs =~ /\/simple_echo\/_load_current_resource.ps1/).should_not be_nil
      (@logs =~ /load current resource for simple echo/).should_not be_nil
      (@logs =~ /\/simple_echo\/echo_text.ps1"/).should_not be_nil
      (@logs =~ /string to echo/).should_not be_nil

      (@logs =~ /\/simple_echo\/_term.ps1/).should_not be_nil
      (@logs =~ /terminating simple echo/).should_not be_nil
    end

    it "should run a recipe accessing the resource" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_recipe_with_resources')
      }
      runner.call.should == true

      # TODO: verify order of execution
      (@logs =~ /\/encode\/_init.ps1/).should_not be_nil
      (@logs =~ /init encode/).should_not be_nil
      (@logs =~ /\/encode\/url_encode.ps1/).should_not be_nil
      (@logs =~ /encode\+this\+is\+a\+string\+with\+spaces/).should_not be_nil

      (@logs =~ /\/echo\/_load_current_resource.ps1/).should_not be_nil
      (@logs =~ /load current resource for echo/).should_not be_nil
      (@logs =~ /\/echo\/echo_text.ps1/).should_not be_nil
      (@logs =~ /echo this is a string with spaces/).should_not be_nil
      (@logs =~ /fourty-two/).should_not be_nil

      (@logs =~ /\/encode\/_init.ps1/).should_not be_nil
      (@logs =~ /init encode/).should_not be_nil
      (@logs =~ /\/encode\/url_encode.ps1/).should_not be_nil
      (@logs =~ /SECOND\+STRING\+TO\+ENCODE/).should_not be_nil

      (@logs =~ /\/echo\/_load_current_resource.ps1/).should_not be_nil
      (@logs =~ /load current resource for echo/).should_not be_nil
      (@logs =~ /\/echo\/echo_text.ps1/).should_not be_nil
      (@logs =~ /SECOND STRING TO ECHO/).should_not be_nil
      (@logs =~ /fourty-two/).should_not be_nil

      (@logs =~ /\/echo\/_term.ps1/).should_not be_nil
      (@logs =~ /terminating echo/).should_not be_nil
    end

    it "should run a recipe with mixed powershell script and powershell provider" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::mix_of_powershell_script_and_powershell_providers')
      }
      runner.call.should == true
      puts @logs
      # TODO: verify order of execution
      (@logs =~ /\/encode\/_init.ps1/).should_not be_nil
      (@logs =~ /init encode/).should_not be_nil
      (@logs =~ /\/encode\/url_encode.ps1/).should_not be_nil
      (@logs =~ /encode\+first/).should_not be_nil

      (@logs =~ /message from powershell script/).should_not be_nil

      (@logs =~ /\/echo\/_load_current_resource.ps1/).should_not be_nil
      (@logs =~ /load current resource for echo/).should_not be_nil
      (@logs =~ /\/echo\/echo_text.ps1/).should_not be_nil
      (@logs =~ /then echo/).should_not be_nil
      (@logs =~ /fourty-two/).should_not be_nil

      (@logs =~ /another powershell message/).should_not be_nil

      (@logs =~ /\/encode\/_init.ps1/).should_not be_nil
      (@logs =~ /init encode/).should_not be_nil
      (@logs =~ /\/encode\/url_encode.ps1/).should_not be_nil
      (@logs =~ /encode\+again/).should_not be_nil

      (@logs =~ /\/echo\/_term.ps1/).should_not be_nil
      (@logs =~ /terminating echo/).should_not be_nil
    end
  end
end