#
# Copyright (c) 2014 RightScale Inc
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

require 'fileutils'
require ::File.expand_path(::File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require ::File.expand_path(::File.join(File.dirname(__FILE__), '..', '..', 'instance', 'spec_helper'))

require ::File.normalize_path(::File.join(::File.dirname(__FILE__), '..', '..', '..', 'lib', 'clouds', 'cloud'))
require ::File.normalize_path(::File.join(::File.dirname(__FILE__), '..', '..', '..', 'lib', 'clouds', 'clouds', 'vsphere'))


describe RightScale::Clouds::Vsphere do

  before(:each) { setup_cloud }
  after(:each)  { teardown_cloud }

  def setup_cloud
    @output_dir = Dir.mktmpdir("vsphere")
    @logger = TestLogger.new()
    @cloud = ::RightScale::Clouds::Vsphere.new(
      :logger => @logger, 
      :name => "vsphere",
      :script_path => "/made/up/path")

    @userdata_file = File.join(@output_dir, 'user.txt')
    @metadata_file = File.join(@output_dir, 'meta.txt')

    @userdata_shellout = "\"#{@cloud.vmtoolsd}\" \"--cmd=info-get guestinfo.userdata\" 2>&1"
    @metadata_shellout = "\"#{@cloud.vmtoolsd}\" \"--cmd=info-get guestinfo.metadata\" 2>&1"

    flexmock(@cloud).should_receive(:vsphere_metadata_location).and_return(@output_dir)
    flexmock(@cloud).should_receive(:fetch_timeout).and_return(2)
    flexmock(@cloud).should_receive(:retry_timeout).and_return(0.1)
    #flexmock(@cloud).should_receive(:vmtoolsd).and_return("vmtoolsd")

  end

  def teardown_cloud
    @cloud.finish()
    FileUtils.rm_rf(@output_dir)
  end


  context "when initializing" do

    it "fails after retry timeout is over" do


      flexmock(@cloud).
        should_receive(:run_command).with(@userdata_shellout).
        and_return(["", 10])
      flexmock(@cloud).
        should_receive(:run_command).with(@metadata_shellout).
        and_return(["", 10])
      result = @cloud.wait_for_instance_ready
      result.exitstatus.should == 10
    end

    it "writes empty files on empty values" do
      @empty_value = "No value found"

      flexmock(@cloud).
        should_receive(:run_command).with(@userdata_shellout).
        and_return(["", 0])
      flexmock(@cloud).
        should_receive(:run_command).with(@metadata_shellout).
        and_return(["", 0])
      result = @cloud.wait_for_instance_ready
      result.exitstatus.should == 0
 
      data = File.read(@userdata_file)
      data.should == ""        

      data = File.read(@metadata_file)
      data.should == "" 
    end


    it "retries whe not ready and on vmtoolsd failures" do
      @userdata_value = "RS_RN_ID=1234&RS_SERVER=us-4.rightscale.com"
      @metadata_not_ready_value = "RS_IP0_IP_ADDRESS=discovering&RS_IP0_ASSIGNMENT=static&VS_INSTANCE_ID=discovering"
      @metadata_ready_value = "RS_IP0_IP_ADDRESS=1.2.3.4&RS_IP0_ASSIGNMENT=static&VS_INSTANCE_ID=vm-999"

      flexmock(@cloud).
        should_receive(:run_command).with(@userdata_shellout).
        and_return(["", 10]).
        and_return(["", 10]).
        and_return([@userdata_value, 0])
      flexmock(@cloud).
        should_receive(:run_command).with(@metadata_shellout).
        and_return(["", 15]).
        and_return([@metadata_not_ready_value, 0]).
        and_return([@metadata_not_ready_value, 0]).
        and_return([@metadata_not_ready_value, 0]).
        and_return([@metadata_ready_value, 0])

      result = @cloud.wait_for_instance_ready
      result.exitstatus.should == 0

      data = File.read(@userdata_file)
      data.should == @userdata_value.gsub("&","\n")        

      data = File.read(@metadata_file)
      data.should == @metadata_ready_value.gsub("&","\n")        

    end
  end

end

