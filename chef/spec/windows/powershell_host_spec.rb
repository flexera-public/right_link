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
  
  require 'fileutils'
  require File.expand_path(File.join(File.dirname(__FILE__), '..', 'mock_auditor_proxy'))
  require File.expand_path(File.join(File.dirname(__FILE__), '..', 'chef_runner'))
  
  
  module PowershellHostSpec
    TEST_TEMP_PATH = File.expand_path(File.join(Dir.tmpdir, "powershell-host-spec-95acb52f-4726-440d-a5be-8de6b249f5d5")).gsub("\\", "/")
    TEST_SCRIPTS_PATH = File.join(TEST_TEMP_PATH, 'scripts')
    TEST_DATA_PATH = File.join(TEST_TEMP_PATH, 'data')
    TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)
    
    def create_script(script_name, script_source)
      script_file_path = File.join(TEST_TEMP_PATH, 'scripts', script_name)
      File.open(File.join(TEST_TEMP_PATH, 'scripts', script_name), 'w') do |f|
        f.puts(script_source)
      end
      
      script_file_path
    end
    module_function :create_script
    
    def run_scripts(&block)
      ready = false
      powershell_host = nil
      EM.run do
        EM.defer do
          begin
            # TODO: add chef node
            powershell_host = RightScale::PowershellHost.new
            
            block.call(powershell_host)
            
          rescue Exception => e
            puts e.message
          ensure
            powershell_host.terminate
            ready = true
          end
        end
        timer = EM::PeriodicTimer.new(0.1) do
          if ready && !powershell_host.active
            timer.cancel
            EM.stop
          end
        end
      end
    end
    module_function :run_scripts
    
    describe RightScale::PowershellHost do
      
      before(:all) do
        @old_logger = Chef::Log.logger
        
        FileUtils.mkdir_p(TEST_SCRIPTS_PATH)
        FileUtils.mkdir_p(TEST_DATA_PATH)
      end
      
      before(:each) do
        Chef::Log.logger = RightScale::Test::MockAuditorProxy.new
      end
      
      after(:all) do
        Chef::Log.logger = @old_logger
        # TODO: delete everything iff the test passes 
        #FileUtils.rm_rf(TEST_TEMP_PATH)
      end
      
      
      it "should redirect stdout to Chef log" do
        PowershellHostSpec.run_scripts do |powershell_host|
          powershell_host.run(PowershellHostSpec.create_script('test_stdout_redirection.ps1', 'echo HelloWorld'))
        end
        
        # TODO: check chef log for 'HelloWorld'
        Chef::Log.logger.info_text.should include("HelloWorld")   
      end

      it "should keep modules loaded by one script available for the next script" do
        PowershellHostSpec.run_scripts do |powershell_host|
          powershell_host.run(PowershellHostSpec.create_script('test_import_propagation_1.ps1','$SystemWebAssembly = [System.Reflection.Assembly]::LoadWithPartialName("System.Web")'))
          powershell_host.run(PowershellHostSpec.create_script('test_import_propagation_2.ps1',
<<EOF
$EncodedUrl = [System.Web.HttpUtility]::UrlEncode("an invalid URL string")
$EncodedUrl
EOF
          ))
        end
        
        # verify string was encoded.
        Chef::Log.logger.info_text.should include("an+invalid+URL+string")
        
      end
    
      it "should propogate environment variables to the next script" do
          PowershellHostSpec.run_scripts do |powershell_host|
            powershell_host.run(PowershellHostSpec.create_script('test_env_propagation_1.ps1', '[Environment]::SetEnvironmentVariable("MY_TEST_VAR", "HelloWorld")'))
            powershell_host.run(PowershellHostSpec.create_script('test_env_propagation_2.ps1', 
<<EOF
$s = [Environment]::GetEnvironmentVariable("MY_TEST_VAR").ToUpper()
for ($i = $s.length - 1; $i -ge 0; $i--) {$reversed = $reversed + ($s.substring($i,1))}
$reversed
EOF
            ))
          end
          
          # verify the string set in the first script was reversed in the second script
          Chef::Log.logger.info_text.should include("DLROWOLLEH")
      end
      
      it "should NOT propogate local powershell variables to the next script" do
          PowershellHostSpec.run_scripts do |powershell_host|
            powershell_host.run(PowershellHostSpec.create_script('test_local_var_propagation_1.ps1', '$s = "Hello World"'))
            powershell_host.run(PowershellHostSpec.create_script('test_local_var_propagation_2.ps1', '$s -eq $null'))
          end
          
          # verify $s is null in the second script
          Chef::Log.logger.info_text.should include("True")
      end
      
      it "should update chef node" do
          pending
      end
      
      it "should stop executing scripts on failure" do
        pending
      end
  end
end

end