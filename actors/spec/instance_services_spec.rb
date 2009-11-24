require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'instance_lib'
require 'instance_services'

describe InstanceServices do

  include RightScale::SpecHelpers

  it 'should update login policy' do
    @mgr = RightScale::LoginManager.instance
    @policy = flexmock(RightScale::LoginPolicy)
    flexmock(@mgr).should_receive(:update_policy).with(@policy).and_return(true)

    @services = InstanceServices.new
    @services.update_login_policy(@policy)
  end

end
