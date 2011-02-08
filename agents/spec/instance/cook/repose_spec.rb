#--  -*- mode: ruby; encoding: utf-8 -*-
# Copyright: Copyright (c) 2011 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..",
                                   "spec_helper"))
require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..",
                                   "..", "payload_types", "lib",
                                   "payload_types"))
require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..",
                                   "lib", "instance", "cook"))
require 'flexmock'

module RightScale
  describe ReposeDownloader do
    include RightScale::SpecHelpers

    class TestException < Exception
      attr_accessor :reason
      def initialize(tuple)
        scope, resource, name, reason = tuple
        scope.should == "scope"
        resource.should == "resource"
        name.should == "name"
        @reason = reason
      end
    end

    before(:all) do
      setup_state
    end

    after(:all) do
      cleanup_state
    end

    before(:each) do
      @downloader = ReposeDownloader.new('scope', 'resource', 'ticket', 'name', TestException, nil)
    end

    context 'with a shimmed HTTP connection' do
      before(:each) do
        @connection = flexmock(:repose_connection)
        flexmock(@downloader).should_receive(:next_repose_server).
          and_return(["a-server", @connection])

        @request = Net::HTTP::Get.new("/#{@scope}/#{@resource}")
        @request['Cookie'] = 'repose_ticket=ticket'
        @request['Host'] = 'a-server'
      end

      it 'should download things that actually exist' do
        response = Net::HTTPSuccess.new("1.1", "200", "everything good")

        @connection.should_receive(:request).with(FlexMock.on {|hash|
                                                    hash[:protocol] == "https" &&
                                                    hash[:server] == "a-server" &&
                                                    hash[:port] == "443" &&
                                                    hash[:request].inspect == @request.inspect
                                                  }, Proc).yields(response).once
        @downloader.request {|r| r.should === response}
      end

      it 'should barf if we get a weird response code' do
        response = Net::HTTPForbidden.new("1.1", "403", "everything bad")

        @connection.should_receive(:request).with(FlexMock.on {|hash|
                                                    hash[:protocol] == "https" &&
                                                    hash[:server] == "a-server" &&
                                                    hash[:port] == "443" &&
                                                    hash[:request].inspect == @request.inspect
                                                  }, Proc).yields(response).once
        lambda { @downloader.request }.should raise_exception(TestException) {|e| e.reason.should == response}
      end

      it 'should retry if we get a 404' do
        bad_response = Net::HTTPNotFound.new("1.1", "404", "everything missing")
        ugly_response = Net::HTTPInternalServerError.new("1.1", "500", "everything ugly")
        good_response = Net::HTTPSuccess.new("1.1", "200", "everything good")

        @connection.should_receive(:request).with(FlexMock.on {|hash|
                                                    hash[:protocol] == "https" &&
                                                    hash[:server] == "a-server" &&
                                                    hash[:port] == "443" &&
                                                    hash[:request].inspect == @request.inspect
                                                  }, Proc).
          yields(bad_response).
          yields(ugly_response).
          yields(good_response).times(3)
        flexmock(@downloader).should_receive(:snooze).with(0).returns(true).once
        flexmock(@downloader).should_receive(:snooze).with(1).returns(true).once
        @downloader.request {|r| r.should === good_response}
      end

      it 'should eventually stop retrying' do
        bad_response = Net::HTTPNotFound.new("1.1", "404", "everything missing")

        @connection.should_receive(:request).with(FlexMock.on {|hash|
                                                    hash[:protocol] == "https" &&
                                                    hash[:server] == "a-server" &&
                                                    hash[:port] == "443" &&
                                                    hash[:request].inspect == @request.inspect
                                                  }, Proc).
          yields(bad_response).at_least.once
        flexmock(@downloader).should_receive(:snooze).with(0).returns(true).once
        flexmock(@downloader).should_receive(:snooze).with(1).returns(true).once
        flexmock(@downloader).should_receive(:snooze).with(2).returns(false).once
        lambda { @downloader.request }.should raise_exception(TestException) {|e| e.reason == "too many attempts"}
      end
    end
  end
end
