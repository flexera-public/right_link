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
require 'chef/mixin/command'


class Chef
  module Mixin
    module Command

      def popen4_with_user(cmd, args={}, &b)
        cmd.sub!(/-u\s[a-zA-Z1-9]*\s?/,"")
        popen4_without_user(cmd, args, &b)
      end
      alias_method_chain :popen4, :user
    end

  end
end

describe Chef::Provider::ExecutableSchedule do
  before(:each) do
    @node = mock("Chef::Node", :null_object => true)
    @resource = Chef::Resource::ExecutableSchedule.new("my_schedule")
    @resource.minute("1")
    @resource.hour("1")
    @resource.day("1")
    @resource.month("1")
    @resource.weekday("1")
    @resource.instance_eval { @cron_resource.user('testuser') }
    @resource.recipe("testrecipe")
  end

  it "should be registered with the default platform hash" do
    Chef::Platform.platforms[:default][:executable_schedule].should_not be_nil
  end

  it "should create a schedule if one with the same name doesnt exist" do
    pending "Existing cron entries, cannot run test" if system('crontab -l')
       #clearing crontab that could have been created by previous tests.
    `crontab -r > /dev/null`
    @provider = Chef::Provider::ExecutableSchedule.new(@node, @resource)
    @provider.load_current_resource

    #Because there is no cron_entry initially, the current_resource should have the default values for min,hour,..
    @provider.current_resource.name.should == @resource.name
    [:minute, :hour, :day, :month, :weekday].each { |attr| @provider.current_resource.send(attr).should == "*" }
    @provider.current_resource.command.should == nil

    @provider.action_create

    #validate that the schedule has been created
    @provider = Chef::Provider::ExecutableSchedule.new(@node, @resource)
    @provider.load_current_resource
    [:minute, :hour, :day, :month, :weekday, :user, :command].each { |attr| @provider.current_resource.send(attr).should == @resource.send(attr) }
  end

  it "should update an already existing schedule" do
    pending "Existing cron entries, cannot run test" if system('crontab -l')
    @resource2 = Chef::Resource::ExecutableSchedule.new("my_schedule")
    @resource2.minute("2")
    @resource2.hour("2")
    @resource2.day("2")
    @resource2.month("2")
    @resource2.weekday("2")
    @resource2.user("testuser")
    @resource2.recipe("testrecipe2")

    @provider = Chef::Provider::ExecutableSchedule.new(@node, @resource2)
    @provider.load_current_resource
    @provider.action_create

    #validate that the schedule has been updated
    @provider = Chef::Provider::ExecutableSchedule.new(@node, @resource)
    @provider.load_current_resource
    [:minute, :hour, :day, :month, :weekday, :user, :command].each { |attr| @provider.current_resource.send(attr).should == @resource2.send(attr) }
  end

  it "should delete an already existing schedule" do
    pending "Existing cron entries, cannot run test" if system('crontab -l')
    @provider = Chef::Provider::ExecutableSchedule.new(@node, @resource)
    @provider.load_current_resource
    @provider.action_delete

    #validate that the schedule has been deleted. when loading for current_resource, it should fill with default values
    @provider.load_current_resource
    @provider.current_resource.user.should == @resource.user
    @provider.current_resource.name.should == @resource.name
    [:minute, :hour, :day, :month, :weekday].each { |attr| @provider.current_resource.send(attr).should == "*" }
    @provider.current_resource.command.should == nil
  end

end



