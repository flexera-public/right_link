#
# Copyright (c) 2011 RightScale Inc
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

require File.expand_path('../spec_helper', __FILE__)

describe RightScale::CloudUtilities do
  before(:each) do
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:depends).and_return(true)
  end

  context '#can_contact_metadata_server?' do
    it 'server responds' do
      t = flexmock("connection")
      flexmock(t).should_receive(:connect_nonblock).and_raise(Errno::EINPROGRESS)
      flexmock(Socket).should_receive(:new).and_return(t)

      flexmock(IO).should_receive(:select).and_return([[], [1], []])

      RightScale::CloudUtilities.can_contact_metadata_server?("1.1.1.1", 80).should be_true
    end

    it 'fails because server responds with nothing' do
      t = flexmock("connection")
      flexmock(t).should_receive(:connect_nonblock).and_raise(Errno::EINPROGRESS)
      flexmock(Socket).should_receive(:new).and_return(t)

      flexmock(IO).should_receive(:select).and_return([[], nil, []])

      RightScale::CloudUtilities.can_contact_metadata_server?("1.1.1.1", 80).should be_false
    end

    it 'fails to connect to server' do
      t = flexmock("connection")
      flexmock(t).should_receive(:connect_nonblock)
      flexmock(Socket).should_receive(:new).and_return(t)

      RightScale::CloudUtilities.can_contact_metadata_server?("1.1.1.1", 80).should be_false
    end

    it 'fails because of a system error' do
      t = flexmock("connection")
      flexmock(t).should_receive(:connect_nonblock).and_raise(Errno::ENOENT)
      flexmock(Socket).should_receive(:new).and_return(t)

      RightScale::CloudUtilities.can_contact_metadata_server?("1.1.1.1", 80).should be_false
    end
  end

end
