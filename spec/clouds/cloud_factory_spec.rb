#
# Copyright (c) 2011 RightScale Inc
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

require ::File.expand_path('../spec_helper', __FILE__)

module RightScale
  class CloudFactorySpec
    CLOUD_NAME = 'connor'
  end
end

describe RightScale::CloudFactory do

  before(:all) do
    @old_names_to_script_paths = RightScale::CloudFactory.instance.reset_registry
    Dir.glob(File.normalize_path(File.join(File.dirname(__FILE__), 'clouds', '*.rb'))).each do |file_path|
      RightScale::CloudFactory.instance.register(File.basename(file_path, '.rb'), file_path)
    end
  end

  before(:each) do
    @output_dir_path = File.join(RightScale::Platform.filesystem.temp_dir, 'rs_cloud_factory_output')

    @mock_static_state_dir = File.join(@output_dir_path, 'rightscale.d')
    @mock_private_bin_dir  = File.join(File.dirname(__FILE__), 'scripts')
    @mock_cloud_file_path  = File.join(@mock_static_state_dir, 'cloud')
    @mock_spool_dir        = File.join(@output_dir_path, "spool")
    @mock_cloud_state_dir  = File.join(@mock_spool_dir, "cloud")
    flexmock(RightScale::AgentConfig).should_receive(:cloud_state_dir).and_return(@mock_cloud_state_dir)

    filesystem = flexmock("filesystem")
    flexmock(RightScale::Platform).should_receive(:filesystem).and_return(filesystem)
    filesystem.should_receive(:right_scale_static_state_dir).and_return(@mock_static_state_dir)
    filesystem.should_receive(:spool_dir).and_return(@mock_spool_dir)
    filesystem.should_receive(:private_bin_dir).and_return(@mock_private_bin_dir)
    filesystem.should_receive(:long_path_to_short_path).and_return { |p| p }

    @logger = flexmock('logger')
    @logged_info = []
    @logger.should_receive(:info).and_return { |m| @logged_info << m; true }
    @logger.should_receive(:debug).by_default
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
  end

  after(:each) do
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
  end

  after(:all) do
    # restore old registry, if necessary
    RightScale::CloudFactory.instance.reset_registry
    if @old_names_to_script_paths
      @old_names_to_script_paths.each do |name, file_path|
        RightScale::CloudFactory.instance.register(name.to_s, file_path) if file_path && File.file?(file_path)
      end
    end
  end

  it 'should raise exception for unknown cloud' do
    lambda{ RightScale::CloudFactory.instance.create('bogus', :logger => @logger) }.should raise_exception RightScale::CloudFactory::UnknownCloud
  end


  it 'should create the default cloud when cloud file exists' do

    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)  # ensure rightscale.d is gone before looking for cloud file
    lambda{ RightScale::CloudFactory.instance.create(RightScale::CloudFactory::UNKNOWN_CLOUD_NAME, :logger => @logger) }.should raise_exception RightScale::CloudFactory::UnknownCloud
    FileUtils.mkdir_p(@mock_static_state_dir)
    File.open(@mock_cloud_file_path, "w") { |f| f.puts(RightScale::CloudFactorySpec::CLOUD_NAME) }
    cloud = RightScale::CloudFactory.instance.create(RightScale::CloudFactory::UNKNOWN_CLOUD_NAME, :logger => @logger)
    cloud.class.should == RightScale::Clouds::Connor
    cloud.name.should == RightScale::CloudFactorySpec::CLOUD_NAME
  end

  it 'should create clouds that can format and write metadata' do
    options = { :logger => @logger }

    # metadata writers output path
    flexmock(RightScale::AgentConfig).should_receive(:cloud_state_dir).and_return(@mock_cloud_state_dir)

    cloud = RightScale::CloudFactory.instance.create(RightScale::CloudFactorySpec::CLOUD_NAME, options)
    cloud.write_metadata
    File.directory?(@mock_cloud_state_dir).should be_true

    # note that the default metadata formatter automatically uses the shortest
    # alias as the prefix for key names (i.e. 'CONNER_') and the dictionary
    # writer automatically converts right-hand values to text and writes the
    # first line or array element only (currently all known metadata values are
    # single lines of text).
    result = JSON.parse(File.read(File.join(@mock_cloud_state_dir, 'meta-data.json')))
    result.should == {"ABC"=>"easy", "abc_123" => {"baby"=>"you"}}

    result = JSON.parse(File.read(File.join(@mock_cloud_state_dir, 'user-data.json')))
    result.should == {"RS_RN_ID"=>"12345", "RS_SERVER"=>"my.rightscale.com"}
  end

  it 'should create clouds that can clear their state' do
    options = { :logger => @logger }
    flexmock(RightScale::AgentConfig).should_receive(:cloud_state_dir).and_return(@mock_cloud_state_dir)

    cloud = RightScale::CloudFactory.instance.create(RightScale::CloudFactorySpec::CLOUD_NAME, options)
    cloud.write_metadata
    File.directory?(@mock_cloud_state_dir).should be_true
    cloud.clear_state
    File.directory?(@mock_cloud_state_dir).should be_false
  end

  it 'should create clouds that can be extended by external scripts' do
    # ensure script can execute (under Linux). note that chmod has no effect
    # in Windows.
    File.chmod(0744, File.join(@mock_private_bin_dir, RightScale::CloudFactorySpec::CLOUD_NAME, 'wait_for_instance_ready.rb'))
    cloud = RightScale::CloudFactory.instance.create(RightScale::CloudFactorySpec::CLOUD_NAME, :logger => @logger)
    result = cloud.wait_for_instance_ready
    result.exitstatus.should == 0
    result.output.should == "Simulating wait for something to happen\nSomething happened!\n"
  end

end
