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

require File.join(File.dirname(__FILE__), 'spec_helper')

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
    @logger = flexmock('logger')
    @logged_info = []
    @logger.should_receive(:info).and_return { |m| @logged_info << m; true }
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
  end

  after(:each) do
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
    @output_dir_path = nil
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

  it 'should register new clouds with multiple aliases' do
    aliases = ['Highlander', 'MacLeod']
    RightScale::CloudFactory.instance.register(aliases, File.join(File.dirname(__FILE__), 'clouds', 'macleod.rb'))
    last_cloud = nil
    (aliases + [RightScale::CloudFactorySpec::CLOUD_NAME] * 2).each do |cloud_alias|
      cloud = RightScale::CloudFactory.instance.create(cloud_alias, :logger => @logger)
      cloud.class.should == RightScale::Cloud
      cloud.name.should == cloud_alias
      last_cloud.should_not == cloud  # factory always returns new instance
      last_cloud = cloud
    end
    last_cloud.logger.should == @logger
    @logged_info.should == ["initialized MacLeod",                        # Highlander
                            "initialized MacLeod",                        # MacLeod
                            "initialized MacLeod", "initialized Connor",  # Connor (inherits MacLeod)
                            "initialized MacLeod", "initialized Connor"]  # Connor (inherits MacLeod)
  end

  it 'should create the default cloud when cloud file exists' do
    mock_state_dir_path = File.join(@output_dir_path, 'rightscale.d')
    mock_cloud_file_path = File.join(mock_state_dir_path, 'cloud')
    spool_dir = RightScale::Platform.filesystem.temp_dir
    filesystem = flexmock("filesystem")
    flexmock(RightScale::Platform).should_receive(:filesystem).and_return(filesystem)
    filesystem.should_receive(:right_scale_state_dir).and_return(mock_state_dir_path)
    filesystem.should_receive(:spool_dir).and_return(spool_dir)
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)  # ensure rightscale.d is gone before looking for cloud file
    lambda{ RightScale::CloudFactory.instance.create(RightScale::CloudFactory::UNKNOWN_CLOUD_NAME, :logger => @logger) }.should raise_exception RightScale::CloudFactory::UnknownCloud
    FileUtils.mkdir_p(mock_state_dir_path)
    File.open(mock_cloud_file_path, "w") { |f| f.puts(RightScale::CloudFactorySpec::CLOUD_NAME) }
    cloud = RightScale::CloudFactory.instance.create(RightScale::CloudFactory::UNKNOWN_CLOUD_NAME, :logger => @logger)
    cloud.class.should == RightScale::Cloud
    cloud.name.should == RightScale::CloudFactorySpec::CLOUD_NAME
  end

  it 'should create clouds that can format and write metadata' do
    options = { :logger => @logger, :metadata_writers => { :output_dir_path => @output_dir_path } }
    cloud = RightScale::CloudFactory.instance.create(RightScale::CloudFactorySpec::CLOUD_NAME, options)
    cloud.write_metadata
    File.directory?(@output_dir_path).should be_true
    writer_type = cloud.metadata_writers.first

    # note that the default metadata formatter automatically uses the shortest
    # alias as the prefix for key names (i.e. 'CONNER_') and the dictionary
    # writer automatically converts right-hand values to text and writes the
    # first line or array element only (currently all known metadata values are
    # single lines of text).
    result = cloud.read_metadata(:cloud_metadata, writer_type)
    result.exitstatus.should == 0
    result.output.should == {"CONNOR_SIMPLE"=>"do re mi", "CONNOR_ABC_123_BABY"=>"you", "CONNOR_ABC"=>"easy"}
    result = cloud.read_metadata(:user_metadata, writer_type)
    result.exitstatus.should == 0
    result.output.should == {"RS_RN_ID"=>"12345", "RS_SERVER"=>"my.rightscale.com"}
  end

  it 'should create clouds that can clear their state' do
    options = { :logger => @logger, :metadata_writers => { :output_dir_path => @output_dir_path } }
    cloud = RightScale::CloudFactory.instance.create(RightScale::CloudFactorySpec::CLOUD_NAME, options)
    cloud.write_metadata
    File.directory?(@output_dir_path).should be_true
    cloud.clear_state
    File.directory?(@output_dir_path).should be_false
  end

  it 'should create clouds that can be extended by external scripts' do
    # ensure script can execute (under Linux). note that chmod has no effect
    # in Windows.
    File.chmod(0744, File.join(File.dirname(__FILE__), 'scripts', RightScale::CloudFactorySpec::CLOUD_NAME, 'wait_for_instance_ready.rb'))
    cloud = RightScale::CloudFactory.instance.create(RightScale::CloudFactorySpec::CLOUD_NAME, :logger => @logger)
    result = cloud.wait_for_instance_ready
    result.exitstatus.should == 0
    result.output.should == "Simulating wait for something to happen\nSomething happened!\n"
  end

end
