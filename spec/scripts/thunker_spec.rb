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
      before(:each) do
        flexmock(STDOUT).should_receive(:puts).by_default
        flexmock(STDERR).should_receive(:puts).by_default
      end
      it 'should fail if required parameter: username is not passed' do
        @options.delete(:username)
        lambda { subject.run(@options) }.should raise_error SystemExit
      end
      it 'should fail if required parameter: email is not passed' do
        @options.delete(:email)
        lambda { subject.run(@options) }.should raise_error SystemExit
      end
      it 'should fail if required parameter: uuid is not passed' do
        @options.delete(:uuid)
        lambda { subject.run(@options) }.should raise_error SystemExit
      end
      it 'should succeed if required parameters are passed' do
        flexmock(RightScale::LoginUserManager).should_receive(:create_user).and_return(@options[:username])
        flexmock(subject).should_receive(:create_audit_entry).and_return(true)
        flexmock(RightScale::LoginUserManager).should_receive(:create_profile).and_return(true)
        flexmock(Kernel).should_receive(:exec).and_return(true)
        flexmock(subject).should_receive(:chown_tty).and_return(true)
        subject.run(@options).should == true
      end
    end

    context 'version' do
      it 'reports RightLink version from gemspec' do
        class Thunker
          def test_version
            version
          end
        end

        subject.test_version.should match /rs_thunk \d+\.\d+\.?\d* - RightLink's thunker \(c\) 2011 RightScale/
      end
    end
  end
end