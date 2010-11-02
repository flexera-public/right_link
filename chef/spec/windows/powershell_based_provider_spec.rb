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

  describe "Powershell::Provider - Given a cookbook containing a powershell provider" do
    include RightScale::Test::MockAuditorProxy

    def is_debug?
      return !!ENV['DEBUG']
    end

    before(:each) do
      @original_logger = ::Chef::Log.logger
      @log_file_name = File.normalize_path(File.join(Dir.tmpdir, "chef_runner_#{File.basename(__FILE__, '.rb')}_#{Time.now.strftime("%Y-%m-%d-%H%M%S")}.log"))
      @log_file = File.open(@log_file_name, 'w')

      # redirect the Chef logs to a file before creating the chef client
      ::Chef::Log.logger = Logger.new(@log_file)
      if is_debug?
        RightScale::RightLinkLog.level = :debug
        RightScale::RightLinkLog = ::Chef::Log.logger
        flexmock(Chef::Log).should_receive(:level).and_return(Logger::DEBUG)
      end

      @logger = RightScale::Test::MockLogger.new
      mock_chef_log(@logger)

      flexmock(RightScale::RightLinkLog).should_receive(:error).and_return { |m| @logger.error_text << m }
      flexmock(RightScale::RightLinkLog).should_receive(:info).and_return { |m| @logger.info_text << m }


      # mock out Powershell script internals so we can run tests using the Powershell script provider
      mock_instance_state = flexmock('MockInstanceState', :past_scripts => [], :record_script_execution => true, :reboot? => false)
      flexmock(Chef::Provider::Powershell).new_instances.should_receive(:instance_state).and_return(mock_instance_state)
    end

    after(:each) do
      # reset the original logger and delete the log file for this run unless explicitly kept
      ::Chef::Log.logger = @original_logger
      @log_file.close rescue nil
      if ENV['RS_LOG_KEEP']
        puts "Log saved to \"#{@log_file_name}\""
      else
        FileUtils.rm_f(@log_file_name)
      end
    end


    it "should run a simple recipe" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_simple_recipe')
      }
      runner.call.should == true
      @logger.error_text.should == ""

      # TODO: verify order of execution
      logs = @logger.info_text.gsub("\n", "")

      logs.scan(/\/simple_encode\/_init.ps1/).length.should == 1 if is_debug?
      logs.scan(/init simple encode/).length.should == 1

      (logs =~ /\/simple_encode\/url_encode.ps1/).should_not be_nil if is_debug?
      (logs =~ /string\+to\+encode/).should_not be_nil

      (logs =~ /\/simple_echo\/_load_current_resource.ps1/).should_not be_nil if is_debug?
      (logs =~ /load current resource for simple echo/).should_not be_nil
      (logs =~ /\/simple_echo\/echo_text.ps1"/).should_not be_nil if is_debug?
      (logs =~ /string to echo/).should_not be_nil

      logs.scan(/\/simple_echo\/_term.ps1/).length.should == 1 if is_debug?
      logs.scan(/terminating simple echo/).length.should == 1
    end

    it "should run a recipe accessing the resource" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_recipe_with_resources')
      }
      runner.call.should == true
      @logger.error_text.should == ""

      # TODO: verify order of execution
      logs = @logger.info_text.gsub("\n", "")
      logs.scan(/\/encode\/_init.ps1/).length.should == 1 if is_debug?
      logs.scan(/init encode/).length.should == 1
      (logs =~ /\/encode\/url_encode.ps1/).should_not be_nil if is_debug?
      (logs =~ /encode\+this\+is\+a\+string\+with\+spaces/).should_not be_nil

      (logs =~ /\/echo\/_load_current_resource.ps1/).should_not be_nil if is_debug?
      (logs =~ /load current resource for echo/).should_not be_nil
      (logs =~ /\/echo\/echo_text.ps1/).should_not be_nil if is_debug?
      (logs =~ /echo this is a string with spaces/).should_not be_nil
      (logs =~ /fourty-two/).should_not be_nil

      (logs =~ /\/encode\/_init.ps1/).should_not be_nil if is_debug?
      (logs =~ /init encode/).should_not be_nil
      (logs =~ /\/encode\/url_encode.ps1/).should_not be_nil if is_debug?
      (logs =~ /SECOND\+STRING\+TO\+ENCODE/).should_not be_nil

      (logs =~ /\/echo\/_load_current_resource.ps1/).should_not be_nil if is_debug?
      (logs =~ /load current resource for echo/).should_not be_nil
      (logs =~ /\/echo\/echo_text.ps1/).should_not be_nil if is_debug?
      (logs =~ /SECOND STRING TO ECHO/).should_not be_nil
      (logs =~ /fourty-two/).should_not be_nil

      (logs =~ /\/echo\/_term.ps1/).should_not be_nil if is_debug?
      (logs =~ /terminating echo/).should_not be_nil
      (logs =~ /break/).should_not be_nil if is_debug?
    end

    it "should run a recipe with mixed powershell script and powershell provider" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::mix_of_powershell_script_and_powershell_providers')
      }
      runner.call.should == true
      @logger.error_text.should == ""

      # TODO: verify order of execution
      logs = @logger.info_text.gsub("\n", "")
      logs.scan(/\/encode\/_init.ps1/).length.should == 1 if is_debug?
      logs.scan(/init encode/).length.should == 1
      (logs =~ /\/encode\/url_encode.ps1/).should_not be_nil if is_debug?
      (logs =~ /encode\+first/).should_not be_nil

      (logs =~ /Running "echo_from_powershell_script"/).should_not be_nil
      (logs =~ /message from powershell script/).should_not be_nil
      (logs =~ /Ran powershell\[echo_from_powershell_script\]/).should_not be_nil

      (logs =~ /\/encode\/url_encode.ps1/).should_not be_nil if is_debug?
      (logs =~ /encode\+again/).should_not be_nil

      (logs =~ /\/echo\/_load_current_resource.ps1/).should_not be_nil if is_debug?
      (logs =~ /load current resource for echo/).should_not be_nil
      (logs =~ /\/echo\/echo_text.ps1/).should_not be_nil if is_debug?
      (logs =~ /then echo/).should_not be_nil
      (logs =~ /fourty-two/).should_not be_nil

      (logs =~ /Running "echo_from_powershell_script_again"/).should_not be_nil
      (logs =~ /another powershell message/).should_not be_nil
      (logs =~ /Ran powershell\[echo_from_powershell_script_again\]/).should_not be_nil

      (logs =~ /Running "echo_from_powershell_script_once_more"/).should_not be_nil
      (logs =~ /another powershell message/).should_not be_nil
      (logs =~ /Ran powershell\[echo_from_powershell_script_once_more\]/).should_not be_nil

      (logs =~ /\/echo\/_load_current_resource.ps1/).should_not be_nil if is_debug?
      (logs =~ /load current resource for echo/).should_not be_nil
      (logs =~ /\/echo\/echo_text.ps1/).should_not be_nil if is_debug?
      (logs =~ /echo again/).should_not be_nil
      (logs =~ /fourty-two/).should_not be_nil

      logs.scan(/\/echo\/_term.ps1/).length.should == 1 if is_debug?
      logs.scan(/terminating echo/).length.should == 1
      (logs =~ /break/).should_not be_nil if is_debug?
    end

    it "should transfer Chef node changes from powershell provider back to ruby" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::modify_chef_node')
      }
      runner.call.should == true

    end

    it "should write debug to output stream when debugging is enabled" do
      # suppress console debug output while testing since powershell debug
      # output is printed to the info stream.
      flexmock(RightScale::RightLinkLog).should_receive(:debug)
      runner = lambda {
        old_level = RightScale::RightLinkLog.level
        begin
          RightScale::RightLinkLog.level = Logger::DEBUG
          RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::debug_output_recipe')
        ensure
          RightScale::RightLinkLog.level = old_level
        end
      }
      runner.call.should == true
      @logger.error_text.should == ""

      logs = @logger.info_text.gsub("\n", "")
      logs.should include("debug message")
      logs.should include("verbose message")
    end

    it "should stop the chef run when a powershell action throws, and be able to run another recipe with the same provider" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_recipe_with_stop_error_action')
      }
      runner.should raise_exception(RightScale::Exceptions::Exec)

      #There 'Should' be string in the error log...
      @logger.error_text.length.should > 0

      @logger.error_text = ""
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_recipe_with_resources')
      }
      runner.should_not raise_error

      #There 'Should' NOT be string in the error log...
      @logger.error_text.should == ""
    end

    it "should stop the chef run when a powershell action exits non-zero, and be able to run another recipe with the same provider" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_recipe_with_nonzero_exit')
      }
      runner.should raise_exception(RightScale::Exceptions::Exec)

      # There 'Should' be string in the error log...
      @logger.error_text.length.should > 0

      @logger.error_text = ""
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_recipe_with_resources')
      }
      runner.should_not raise_error

      #There 'Should' NOT be string in the error log...
      @logger.error_text.should == ""
    end

    it "should produce a readable powershell error when script is stopped by error action" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_recipe_with_stop_error_action')
      }
      runner.should raise_exception(RightScale::Exceptions::Exec)

      #There 'Should' be string in the error log...
      @logger.error_text.length.should > 0
      errors = @logger.error_text.gsub(/\s+/, "")
      errors.should match("Unexpected exit code from action. Expected 0 but returned 1.  Script".gsub(/\s+/, ""))

      message_format = <<-EOF
Get-Item : Cannot find path '.*foo' because it does not exist.
At .*fail_with_stop_error_action.ps1:2 char:9
+ Get-Item <<<<  "foo" -ea Stop
    + CategoryInfo          : ObjectNotFound: (.*foo:String) [Get-Item], ItemNotFoundException
    + FullyQualifiedErrorId : PathNotFound,Microsoft.PowerShell.Commands.GetItemCommand
    +
    + Script error near:
    + 1:    $testvar = 1
    + 2:    Get-Item  <<<< "foo" -ea Stop
    + 3:    exit
EOF
      # replace newlines and spaces
      expected_message = Regexp.escape(message_format.gsub(/\s+/, ""))

      # un-escape the escaped regex strings
      expected_message.gsub!("\\.\\*", ".*")

      # find the log message
      errors.should match(expected_message)
    end

    it "should produce a readable powershell error when script explicitly throws an exception" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_recipe_with_explicit_throw')
      }
      runner.should raise_exception(RightScale::Exceptions::Exec)

      #There 'Should' be string in the error log...
      @logger.error_text.length.should > 0
      errors = @logger.error_text.gsub(/\s+/, "")
      errors.should match("Unexpected exit code from action. Expected 0 but returned 1.  Script".gsub(/\s+/, ""))

      message_format = <<-EOF
explicitly throwing
At .*fail_with_explicit_throw.ps1:2 char:6
+ throw <<<<  "explicitly throwing"
    + CategoryInfo          : OperationStopped: (explicitly throwing:String) [], RuntimeException
    + FullyQualifiedErrorId : explicitly throwing
    +
    + Script error near:
    + 1:        $testvar = 1
    + 2:        throw <<<< "explicitly throwing"
    + 3:        exit
EOF
      # replace newlines and spaces
      expected_message = Regexp.escape(message_format.gsub(/\s+/, ""))

      # un-escape the escaped regex strings
      expected_message.gsub!("\\.\\*", ".*")

      # find the log message
      errors.should match(expected_message)
    end

    it "should produce a readable powershell error when script invokes a bogus cmdlet" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_recipe_with_bogus_cmdlet')
      }
      runner.should raise_exception(RightScale::Exceptions::Exec)

      #There 'Should' be string in the error log...
      @logger.error_text.length.should > 0
      errors = @logger.error_text.gsub(/\s+/, "")
      errors.should match("Unexpected exit code from action. Expected 0 but returned 1.  Script".gsub(/\s+/, ""))

      message_format = <<-EOF
The term 'bogus_cmdlet_name' is not recognized as the name of a cmdlet, function, script file, or operable program. Che
ck the spelling of the name, or if a path was included, verify that the path is correct and try again.
At .*fail_with_bogus_cmdlet.ps1:2 char:18
+ bogus_cmdlet_name <<<<  1 "abc"
    + CategoryInfo          : ObjectNotFound: (bogus_cmdlet_name:String) [], CommandNotFoundException
    + FullyQualifiedErrorId : CommandNotFoundException
    +
    + Script error near:
    + 1:        $testvar = 1
    + 2:        bogus_cmdlet_name <<<< 1 "abc"
    + 3:        exit
EOF
      # replace newlines and spaces
      expected_message = Regexp.escape(message_format.gsub(/\s+/, ""))

      # un-escape the escaped regex strings
      expected_message.gsub!("\\.\\*", ".*")

      # find the log message
      errors.should match(expected_message)
    end

    it "should produce a readable powershell error when a cmdlet is piped with inputs missing" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(PowershellBasedProviderSpec::TEST_COOKBOOK_PATH, 'test_cookbook::run_powershell_based_recipe_with_missing_piped_input')
      }
      runner.should raise_exception(RightScale::Exceptions::Exec)

      @logger.error_text.length.should > 0
      errors = @logger.error_text.gsub(/\s+/, "")
      errors.should match("Unexpected exit code from action. Expected 0 but returned 1.  Script".gsub(/\s+/, ""))

      message_format = <<-EOF
ConvertTo-SecureString : Input string was not in a correct format.
At .*fail_with_missing_piped_input.ps1:3 char:75
+ $securePassword = write-output $plainTextPassword | ConvertTo-SecureString <<<<
    + CategoryInfo          : NotSpecified: (:) [ConvertTo-SecureString], FormatException
    + FullyQualifiedErrorId : System.FormatException,Microsoft.PowerShell.Commands.ConvertToSecureStringCommand
    +
    + Script error near:
    + 1:        # note that there are intentionally not enough arguments for ConvertTo-SecureString
    + 2:        $plainTextPassword = 'Secret123!'
    + 3:        $securePassword = write-output $plainTextPassword | ConvertTo-SecureString <<<<
EOF
      # replace newlines and spaces
      expected_message = Regexp.escape(message_format.gsub(/\s+/, ""))

      # un-escape the escaped regex strings
      expected_message.gsub!("\\.\\*", ".*")

      # find the log message
      errors.should match(expected_message)
    end

  end
end
