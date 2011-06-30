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

require File.join(File.dirname(__FILE__), 'spec_helper')

describe RightScale::IdempotentRequest do

  module RightScale
    class SenderMock
      include Singleton
    end
  end

  before(:all) do
    if @sender_exists = RightScale.const_defined?(:Sender)
      RightScale.module_eval('OldSender = Sender')
    end
    RightScale.module_eval('Sender = SenderMock')
  end

  after(:all) do
    if @sender_exists
      RightScale.module_eval('Sender = OldSender')
    end
  end

  it 'should retry non-delivery responses' do
    request = RightScale::IdempotentRequest.new('type', 'payload')
    flexmock(RightScale::Sender.instance).should_receive(:send_retryable_request).with('type', 'payload', 
      nil, { :offline_queueing => true }, Proc).and_yield(RightScale::OperationResult.non_delivery('test')).once
    flexmock(EM).should_receive(:add_timer).with(RightScale::IdempotentRequest::RETRY_DELAY, Proc).once
    request.run
  end

  it 'should retry retry responses' do
    request = RightScale::IdempotentRequest.new('type', 'payload')
    flexmock(RightScale::Sender.instance).should_receive(:send_retryable_request).with('type', 'payload', 
      nil, { :offline_queueing => true }, Proc).and_yield(RightScale::OperationResult.retry('test')).once
    flexmock(EM).should_receive(:add_timer).with(RightScale::IdempotentRequest::RETRY_DELAY, Proc).once
    request.run
  end

  it 'should fail in case of error responses by default' do
    request = RightScale::IdempotentRequest.new('type', 'payload')
    flexmock(RightScale::Sender.instance).should_receive(:send_retryable_request).with('type', 'payload', 
      nil, { :offline_queueing => true }, Proc).and_yield(RightScale::OperationResult.error('test')).once
    flexmock(request).should_receive(:fail).once
    request.run
  end

  it 'should retry error responses when told to' do
    request = RightScale::IdempotentRequest.new('type', 'payload', retry_on_error=true)
    flexmock(RightScale::Sender.instance).should_receive(:send_retryable_request).with('type', 'payload',
      nil, { :offline_queueing => true }, Proc).and_yield(RightScale::OperationResult.error('test')).once
    flexmock(EM).should_receive(:add_timer).with(RightScale::IdempotentRequest::RETRY_DELAY, Proc).once
    request.run
  end

  it 'should ignore responses that arrive post-cancel' do
    request = RightScale::IdempotentRequest.new('type', 'payload')
    flexmock(RightScale::Sender.instance).should_receive(:send_retryable_request).with('type', 'payload',
      nil, { :offline_queueing => true }, Proc).and_yield(RightScale::OperationResult.success('test')).once
    flexmock(request).should_receive(:fail).once
    flexmock(request).should_receive(:succeed).never
    flexmock(EM).should_receive(:add_timer).with(RightScale::IdempotentRequest::RETRY_DELAY, Proc).never
    request.cancel('test')
    request.run
  end

  it 'should ignore duplicate responses' do
    request = RightScale::IdempotentRequest.new('type', 'payload', retry_on_error=true)
    flexmock(RightScale::Sender.instance).should_receive(:send_retryable_request).and_return do |t, p, n, o, b|
      5.times { b.call(RightScale::OperationResult.success('test')) }
    end
    flexmock(request).should_receive(:fail).never
    flexmock(request).should_receive(:succeed).once
    flexmock(EM).should_receive(:add_timer).with(RightScale::IdempotentRequest::RETRY_DELAY, Proc).never
    request.run
  end

end
