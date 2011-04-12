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

require File.join(File.dirname(__FILE__), 'spec_helper')

unless RightScale::RightLinkConfig[:platform].windows?  # FIX: chef's cron isn't portable to windows, do we want to reimplement this provider?

require 'chef/mixin/command'

class Chef
  module Mixin
    module Command

      # remove user argument so tests don't have to be run as root
      def popen4_with_user(cmd, args={}, &b)
        cmd.sub!(/-u\s[a-zA-Z1-9]*\s?/,"")
        popen4_without_user(cmd, args, &b)
      end
      alias :popen4_without_user :popen4
      alias :popen4 :popen4_with_user
    end

  end
end

describe Chef::Provider::ExecutableSchedule do
  before(:each) do
    @node = flexmock('Chef::Node')
    @node.should_ignore_missing
    @run_context = Chef::RunContext.new(@node, {})
    @resource = Chef::Resource::ExecutableSchedule.new('my_schedule', @run_context)
    @resource.minute('1')
    @resource.hour('1')
    @resource.day('1')
    @resource.month('1')
    @resource.weekday('1')
    @resource.instance_eval { @cron_resource.user('testuser') }
    @resource.recipe("testrecipe")
    flexmock(Chef::Log).should_receive(:info)
  end

  it "should be registered with the default platform hash" do
    Chef::Platform.platforms[:default][:executable_schedule].should_not be_nil
  end

  it "should create a schedule if one with the same name doesnt exist" do
    begin
      pending "Non crontab executable on this machine" unless system('which crontab')
      pending "Existing cron entries, cannot run test" if system('crontab -l 2>/dev/null')

      @provider = Chef::Provider::ExecutableSchedule.new(@resource, @run_context)
      @provider.load_current_resource

      #Because there is no cron_entry initially, the current_resource should have the default values for min,hour,..
      @provider.current_resource.name.should == @resource.name
      [:minute, :hour, :day, :month, :weekday].each { |attr| @provider.current_resource.send(attr).should == "*" }
      @provider.current_resource.command.should == nil

      @provider.action_create

      #validate that the schedule has been created
      @provider = Chef::Provider::ExecutableSchedule.new(@resource, @run_context)
      @provider.load_current_resource
      [:minute, :hour, :day, :month, :weekday].each { |attr| @provider.current_resource.send(attr).should == @resource.send(attr) }
    ensure
      `crontab -r`
    end
  end

  it "should update an already existing schedule" do
    begin
      pending "Non crontab executable on this machine" unless system('which crontab')
      pending "Existing cron entries, cannot run test" if system('crontab -l 2>/dev/null')

      @resource2 = Chef::Resource::ExecutableSchedule.new("my_schedule", @run_context)
      @resource2.minute("2")
      @resource2.hour("2")
      @resource2.day("2")
      @resource2.month("2")
      @resource2.weekday("2")

      @provider = Chef::Provider::ExecutableSchedule.new(@resource2, @run_context)
      @provider.load_current_resource
      @provider.action_create

      #validate that the schedule has been updated
      @provider = Chef::Provider::ExecutableSchedule.new(@resource2, @run_context)
      @provider.load_current_resource
      [:minute, :hour, :day, :month, :weekday].each { |attr| @provider.current_resource.send(attr).should == @resource2.send(attr) }
    ensure
      `crontab -r`
    end
  end

  it "should delete an already existing schedule" do
    pending "Non crontab executable on this machine" unless system('which crontab')
    pending "Existing cron entries, cannot run test" if system('crontab -l 2>/dev/null')
    pending "Chef.popen4 is raising Errno::EBADF for some runs of this test...needs more investigation"

    begin
      @provider = Chef::Provider::ExecutableSchedule.new(@resource, @run_context)
      @provider.load_current_resource
      @provider.action_create
      @provider.load_current_resource
      [:minute, :hour, :day, :month, :weekday].each { |attr| @provider.current_resource.send(attr).should == @resource.send(attr) }
      @provider.action_delete

      #validate that the schedule has been deleted. when loading for current_resource, it should fill with default values
      @provider.load_current_resource
      @provider.current_resource.name.should == @resource.name
      [:minute, :hour, :day, :month, :weekday].each { |attr| @provider.current_resource.send(attr).should == "*" }
      @provider.current_resource.command.should == nil
    ensure
      `crontab -r 2>/dev/null`
    end
  end

end

end  # unless windows
