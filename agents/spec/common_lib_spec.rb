require File.join(File.dirname(__FILE__), 'spec_helper')

describe "common_lib" do

  describe "when ensuring a mapper exists" do

    describe "with a configured mapper proxy" do
      before(:each) do
        RightScale.instance_variable_set(:@mapper_proxy, nil)
        RightScale::MapperProxy.stub!(:instance).and_return(mock(:mapper_proxy))
      end
      
      it "should not raise an error" do
        lambda {
          RightScale.ensure_mapper_proxy
        }.should_not raise_error
      end
      
      it "should set the mapper instance variable to the mapper proxy instance" do
        RightScale.ensure_mapper_proxy
        RightScale.mapper_proxy.should == RightScale::MapperProxy.instance
      end
    end
    
    describe "when the mapper proxy wasn't created yet" do
      before do
        RightScale.instance_variable_set(:@mapper_proxy, nil)
        RightScale::MapperProxy.stub!(:instance).and_return(nil)
      end
      
      it "should raise an error" do
        lambda {
          RightScale.ensure_mapper_proxy
        }.should raise_error(RightScale::MapperProxyNotRunning)
      end
    end
  end
end