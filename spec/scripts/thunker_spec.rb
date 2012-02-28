# Copyright (c) 2009-2011 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'thunker'))

module RightScale
  describe Thunker do
    before(:each) do
      @options = {
        :username => 'username',
        :email    => 'email',
        :uuid     => 123
      }
    end
    context '.run' do
      it 'should fail if required parameters are not passed' do
        @options.delete(:username)
        lambda { subject.run(@options) }.should raise_error SystemExit
      end
      it 'should fail if required parameters are not passed' do
        @options.delete(:email)
        lambda { subject.run(@options) }.should raise_error SystemExit
      end
      it 'should fail if required parameters are not passed' do
        @options.delete(:uuid)
        lambda { subject.run(@options) }.should raise_error SystemExit
      end
      it 'should succeed if required parameters are passed' do
        flexmock(RightScale::LoginManager).should_receive(:create_user).and_return(@options[:username])
        flexmock(subject).should_receive(:create_audit_entry).and_return(true)
        flexmock(RightScale::LoginManager).should_receive(:create_profile).and_return(true)
        flexmock(Kernel).should_receive(:exec).and_return(true)
        subject.run(@options).should == true
      end
    end
  end
end