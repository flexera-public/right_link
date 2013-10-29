#
# Copyright (c) 2013 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'cook'))

module RightScale
  describe ConcurrentReposeDownloader do
    let(:hostname)    { 'repose-hostname' }
    let(:audit)       { flexmock('audit') }
    let(:subject)     { ConcurrentReposeDownloader.new([hostname], audit) }

    context '#downlad' do
      it "should run repose_get script to download requested resources" do
        cmd = /.*repose_get.*--resource resource --out-file out_file repose-hostname/
        flexmock(RightScale::RightPopen).should_receive(:popen3_async).with(cmd, Hash).and_return(true)
        subject.download("resource", "out_file")

      end
      it "queue downloads if there are more than #{ConcurrentReposeDownloader::MAX_CONCURRENCY} running downloads" do
        subject.instance_variable_set(:@running_downloads, ConcurrentReposeDownloader::MAX_CONCURRENCY)
        flexmock(RightScale::RightPopen).should_receive(:popen3_async).never
        subject.download("resource", "out_file")
        subject.instance_variable_get(:@download_queue).should == [["resource", "out_file"]]
      end
    end
    context "#join" do
      it "should wait till all in-progress downloads complete" do
        subject.instance_variable_set(:@running_downloads, 1)
        flexmock(subject).should_receive(:sleep).with(0.1).at_least.once.and_return {|t| subject.instance_variable_set(:@running_downloads, 0) }
        subject.join
      end
      it "should return true if everything succeeded" do
        status = flexmock("status")
        status.should_receive(:success?).and_return(true)
        subject.send(:on_exit, status)
        subject.join.should == true
      end
      it "should return false if any process failed" do
        status = flexmock("status")
        status.should_receive(:success?).and_return(false)
        subject.send(:on_exit, status)
        subject.join.should == false
      end
    end
  end
end
