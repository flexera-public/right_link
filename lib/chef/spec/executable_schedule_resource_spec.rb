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

describe Chef::Resource::ExecutableSchedule do
  
  before(:each) do
    @resource = Chef::Resource::ExecutableSchedule.new("testing")
    @resource.name.should == "testing"
  end  
 
  it "should create a new Chef::Resource::ExecutableSchedule" do
      @resource.should be_a_kind_of(Chef::Resource)
      @resource.should be_a_kind_of(Chef::Resource::ExecutableSchedule)
    end

  it "should have a name of executable schedule" do
    @resource.resource_name.should == :executable_schedule
  end

  it "should set the defaults correctly" do
    @resource.action.should == :create
    @resource.minute.should == "*"
    @resource.hour.should == "*"
    @resource.day.should == "*"
    @resource.month.should == "*"
    @resource.weekday.should == "*"
    @resource.recipe.should == nil
    @resource.recipe_id.should == nil
    @resource.right_script.should == nil
    @resource.right_script_id.should == nil

  end

  it "should read/write attributes from the underlying cron_resource" do
    attrs = {:minute => "1", :hour => "1", :day => "2", :month => "1", :weekday => "3" }
    attrs.each do |attr, value|
      @resource.send(attr, value)
      @resource.send(attr).should == @resource.cron_resource.send(attr)
    end

  end
  
  it "should accept valid schedule parameters" do
    parameters = {
      :minute => {
        :range_error    => ["60"],
        :valid          => ["0","25","59","*"]
      },
      :hour => {
        :range_error    => ["24"],
        :valid          => ["0","12","23","*"]
      },
      :day => {
        :range_error    => ["32"],
        :valid          => ["1","12","31","*"]
      },
      :month => {
        :range_error    => ["13"],
        :valid          => ["1","5","12","*"]
      },
      :weekday => {
        :range_error    => ["8"],
        :valid          => ["0","4","7","*"]
      }
    }
    parameters.each do |time_attr, input_cases|
      input_cases.each do |input_case, inputs|
        if(input_case == :range_error)
          inputs.each {|input| lambda { @resource.send(time_attr,input)}.should raise_error(RangeError)}
        else
          inputs.each {|input| lambda { @resource.send(time_attr,input)}.should_not raise_error(RangeError)}
        end
      end
    end
  end

  it "should accept a valid right_script_id/recipe_id option" do
    lambda { @resource.right_script_id "someuser" }.should raise_error(ArgumentError)
    lambda { @resource.right_script_id "-1" }.should raise_error(RangeError)
    lambda { @resource.right_script_id :unsupported }.should raise_error(ArgumentError)
    
    lambda { @resource.recipe_id "someuser" }.should raise_error(ArgumentError)
    lambda { @resource.recipe_id "-1" }.should raise_error(RangeError)
    lambda { @resource.recipe_id :unsupported }.should raise_error(ArgumentError)
  end

  it "should set the command correctly when any of the right_script(_id) or recipe(_id) is set" do
    @resource.right_script "db_backup"
    @resource.instance_variable_get(:@cron_resource).command.should == "rs_run_right_script -n db_backup"
    
    @resource.right_script_id "123"
    @resource.instance_variable_get(:@cron_resource).command.should == "rs_run_right_script -i 123"

    @resource.recipe "db_backup_recipe"
    @resource.instance_variable_get(:@cron_resource).command.should == "rs_run_recipe -n db_backup_recipe"

    @resource.recipe_id "456"
    @resource.instance_variable_get(:@cron_resource).command.should == "rs_run_recipe -i 456"
  end

end



