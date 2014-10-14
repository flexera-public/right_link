#
# Copyright (c) 2009-2011 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

describe RightScale::LoginUserManager do
  include RightScale::SpecHelper

  subject { RightScale::LoginUserManager.instance }

  before(:each) do
    flexmock(RightScale::Log).should_receive(:debug).by_default
  end

  context :pick_username do
    context "given a name is taken" do
      before(:each) do
        flexmock(subject).should_receive(:user_exists?).with('joe').and_return(true)
      end

      it 'picks the best alternative' do
        flexmock(subject).should_receive(:user_exists?).with('joe_1').and_return(false)

        subject.pick_username('joe').should == 'joe_1'
      end

      it 'picks any available alternative' do
        @n = 1
        3.times do
          flexmock(subject).should_receive(:user_exists?).with("joe_#{@n}").and_return(true)
          @n += 1
        end
        flexmock(subject).should_receive(:user_exists?).with("joe_#{@n}").and_return(false)

        subject.pick_username('joe').should == "joe_#{@n}"
      end
    end

    context "given a username does not exist" do
      before(:each) do
        flexmock(subject).should_receive(:user_exists?).with('joe').and_return(false)
      end

      it 'picks the ideal name' do
        subject.pick_username('joe').should == 'joe'
      end
    end
  end
end
