# Copyright (c) 2010-2013 RightScale Inc
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

if RightScale::Platform.windows?

CHEF_WINDOWS_BASE_DIR = File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'chef', 'windows')

require File.normalize_path(File.join(CHEF_WINDOWS_BASE_DIR, 'dynamic_powershell_provider'))
require File.normalize_path(File.join(CHEF_WINDOWS_BASE_DIR, 'powershell_provider_base'))
require File.normalize_path(File.join(CHEF_WINDOWS_BASE_DIR, 'powershell_host'))

describe RightScale::DynamicPowershellProvider do

  before(:each) do
    @provider = RightScale::DynamicPowershellProvider.new
  end

  it 'should create Powershell provider classes dynamically' do
    init = lambda { |p|
      p.instance_eval("def init1;end")
      p.class_eval("def test1;end")
    }
    @provider.send(:create_provider_class, 'TestMod::TestSubMod::TestProvider', Object, &init)
    Object.const_defined?('TestMod').should be_true
    TestMod.const_defined?('TestSubMod').should be_true
    TestMod::TestSubMod.const_defined?('TestProvider').should be_true
    (TestMod::TestSubMod::TestProvider.instance_methods - RightScale::PowershellProviderBase.instance_methods).map(&:to_s).should == %w[test1]
    (TestMod::TestSubMod::TestProvider.methods - RightScale::PowershellProviderBase.methods).map(&:to_s).sort.should == %w[init1]
  end

  it 'should undefine methods of previously created Powershell providers' do
    init = lambda { |p|
      p.class_eval("def test1;end")
    }
    init2 = lambda { |p|
      p.class_eval("def test2;end")
    }
    @provider.send(:create_provider_class, 'TestMod::TestSubMod::TestProvider', Object, &init)
    @provider.send(:create_provider_class, 'TestMod::TestSubMod::TestProvider', Object, &init2)
    Object.const_defined?('TestMod').should be_true
    TestMod.const_defined?('TestSubMod').should be_true
    TestMod::TestSubMod.const_defined?('TestProvider').should be_true
    (TestMod::TestSubMod::TestProvider.instance_methods - RightScale::PowershellProviderBase.instance_methods).map(&:to_s).should == %w[test2]
  end

  describe 'given valid action scripts' do

    before(:each) do
      @cookbooks_dir = File.join(::Dir.tmpdir, 'dynamic_powershell_provider_spec-c91f9f99a1ffe8fb9a2117ce91bda7e5')
      @scripts_dir = File.join(@cookbooks_dir, 'cookbook', 'powershell_providers', 'scripts')
      FileUtils.mkdir_p(@scripts_dir)
      @init_script = File.normalize_path(File.join(@scripts_dir, '_init.ps1'))
      File.open(@init_script, 'w') { |f| f.puts 42 }
      @load_script = File.normalize_path(File.join(@scripts_dir, '_load_current_resource.ps1'))
      File.open(@load_script, 'w') { |f| f.puts 42 }
      @action1_script = File.normalize_path(File.join(@scripts_dir, 'action1.ps1'))
      File.open(@action1_script, 'w') { |f| f.puts 42 }
      @action2_script = File.normalize_path(File.join(@scripts_dir, 'action2.ps1'))
      File.open(@action2_script, 'w') { |f| f.puts 42 }
      @instance_methods = [ @action1_script, @action2_script ].map { |s| 'action_' + File.basename(s, '.*').snake_case }
      @instance_methods << 'load_current_resource'

      @scripts_dir2 = File.join(@cookbooks_dir, 'cookbook2', 'powershell_providers', 'scripts')
      FileUtils.mkdir_p(@scripts_dir2)
      @term_script = File.normalize_path(File.join(@scripts_dir2, '_term.ps1'))
      File.open(@term_script, 'w') { |f| f.puts 42 }
      @instance_methods2 = []
    end

    after(:each) do
      FileUtils.rm_rf(@cookbooks_dir)
    end

    it 'should generate the correct actions' do
      @provider.generate_providers(@cookbooks_dir)
      Object.const_defined?(:CookbookScripts).should be_true
      Object.const_defined?(:Cookbook2Scripts).should be_true
      @provider.providers.map(&:to_s).sort.should == %w[Cookbook2Scripts CookbookScripts]
      (CookbookScripts.instance_methods - RightScale::PowershellProviderBase.instance_methods + %w[load_current_resource]).map(&:to_s).sort.should == @instance_methods
      (CookbookScripts.methods - Chef::Provider.methods).map(&:to_s).sort.should == %w[init run_script terminate]
      (Cookbook2Scripts.instance_methods - RightScale::PowershellProviderBase.instance_methods).sort.should == @instance_methods2
      (Cookbook2Scripts.methods - Chef::Provider.methods).map(&:to_s).sort.should == %w[init run_script terminate]
      host_mock = flexmock('PowershellHost')
      flexmock(RightScale::PowershellHost).should_receive(:new).and_return(host_mock)
      host_mock.should_receive(:active).and_return(true)
      host_mock.should_receive(:run).once.with(@init_script).ordered
      host_mock.should_receive(:run).once.with(@load_script).ordered
      host_mock.should_receive(:run).once.with(@action1_script).ordered
      host_mock.should_receive(:run).once.with(@action2_script).ordered
      host_mock.should_receive(:terminate).once.ordered
      host_mock.should_receive(:run).once.with(@term_script).ordered
      host_mock.should_receive(:terminate).once.ordered

      Chef::Resource.const_set('CookbookScripts', Class.new(Chef::Resource))
      resource = flexmock('Resource', :cookbook_name => 'cookbook', :name => 'foo')
      cb = CookbookScripts.new(resource, flexmock(:node => nil))
      cb.load_current_resource
      cb.action_action1
      cb.action_action2
      CookbookScripts.terminate
      Cookbook2Scripts.init(nil)
      Cookbook2Scripts.terminate
    end

  end
end

end # if windows?
