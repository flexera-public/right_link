#
# Copyright (c) 2009 RightScale Inc
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
require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')

# The daemonize method of AR clashes with the daemonize Chef attribute, we don't need that method so undef it
undef :daemonize if methods.include?('daemonize')

require 'chef'
require 'log_resource'

describe Chef::Resource::Log do

  before(:each) do
    @log_str = "this is my string to log"
    @resource = Chef::Resource::Log.new(@log_str)
  end  
 
  it "should create a new Chef::Resource::Log" do
      @resource.should be_a_kind_of(Chef::Resource)
      @resource.should be_a_kind_of(Chef::Resource::Log)
    end

  it "should have a name of log" do
    @resource.resource_name.should == :log
  end

  it "should allow you to set a log string" do
    @resource.name.should == @log_str
  end
  
  it "should accept a vaild level option" do
    lambda { @resource.level :debug }.should_not raise_error(ArgumentError)
    lambda { @resource.level :info }.should_not raise_error(ArgumentError)
    lambda { @resource.level :warn }.should_not raise_error(ArgumentError)
    lambda { @resource.level :error }.should_not raise_error(ArgumentError)
    lambda { @resource.level :fatal }.should_not raise_error(ArgumentError)
    lambda { @resource.level :unsupported }.should raise_error(ArgumentError)
  end

end
  
