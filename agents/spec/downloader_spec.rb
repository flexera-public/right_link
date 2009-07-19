require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'downloader'

describe RightScale::Downloader do

  before(:all) do
    @dest_dir = new_folder_path
    @valid_url = 'http://www.rightscale.com/images/btn_tryFree.png'
    @wrong_url = 'http://www.rightscale.com/images/btn_tryFree.png2'
  end

  before(:each) do
    @downloader = RightScale::Downloader.new
  end
 
  after(:all) do
    FileUtils.rm_rf(@dest_dir) if File.exist?(@dest_dir)
  end

  it 'should report initialize defaults' do
    @downloader.retry_period.should_not be_nil
    @downloader.use_backoff.should_not be_nil
    @downloader.max_retry_period.should_not be_nil
  end

  it 'should report invalid download path' do
    @downloader.download(@valid_url, '/').should be_false
    @downloader.error.should_not be_nil
    @downloader.successful?.should be_false
  end

  it 'should report invalid URLs' do
    @downloader.max_retry_period = 1
    @downloader.download(@wrong_url, File.join(@dest_dir, 'test0'), user=nil, pass=nil, 1).should be_false
    @downloader.successful?.should be_false
    @downloader.error.should_not be_nil
  end

  it 'should retry' do
    time = Time.now
    @downloader.use_backoff = false
    @downloader.retry_period = 0.1
    retry_count = 0
    res = @downloader.download(@wrong_url, File.join(@dest_dir, 'test1'), user=nil, pass=nil, 3) { retry_count += 1 }
    res.should be_false
    retry_count.should == 3
    @downloader.successful?.should be_false
    @downloader.error.should_not be_nil
  end

  it 'should download' do
    @downloader.download(@valid_url, File.join(@dest_dir, 'test2')).should be_true
    @downloader.successful?.should be_true
    @downloader.error.should be_nil
  end

  it 'should override files' do
    @downloader.download(@valid_url, File.join(@dest_dir, 'test3')).should be_true
    @downloader.successful?.should be_true
    @downloader.error.should be_nil
    @downloader.download(@valid_url, File.join(@dest_dir, 'test3')).should be_true
    @downloader.successful?.should be_true
    @downloader.error.should be_nil
  end

  it 'should reset last error' do
    @downloader.download(@valid_url, '/').should be_false
    @downloader.error.should_not be_nil
    @downloader.successful?.should be_false
    @downloader.download(@valid_url, File.join(@dest_dir, 'test4')).should be_true
    @downloader.successful?.should be_true
    @downloader.error.should be_nil
  end

  it 'should calculate scales' do
    @downloader.send(:scale, 0).should == [0, 'B']
    @downloader.send(:scale, 1023).should == [1023, 'B']
    @downloader.send(:scale, 1024).should == [1, 'KB']
    @downloader.send(:scale, 1024**2 - 1).should == [(1024**2 - 1) / 1024, 'KB']
    @downloader.send(:scale, 1024**2).should == [1, 'MB']
    @downloader.send(:scale, 1024**3 - 1).should == [(1024**3 - 1) / 1024**2, 'MB']
    @downloader.send(:scale, 1024**3).should == [1, 'GB']
  end

  # Path to non-existant folder in this directory
  def new_folder_path
    folder = nil
    begin
      folder = File.join(File.dirname(__FILE__), rand(10000000).to_s)
    end until !File.exist?(folder)
    folder
  end

end