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
#
require File.expand_path('../spec_helper', __FILE__)

module RightScale
  module AgentConnection
    STOP_TIMEOUT = 0.1  # monkey-patch stop timeout for quick testing
  end
end

describe RightScale::AuditStub do

  include ::RightScale::SpecHelper

  before(:each) do
    @cookie = 'cookie'
    @thread_name = 'some thread name'
    @audit_connection = nil
    port = 42
    clazz = Class.new { include ::RightScale::AgentConnection }
    @audit_connection = flexmock(clazz.new(@cookie, @thread_name))
    flexmock(::EventMachine).
      should_receive(:connect).with('127.0.0.1', port, ::RightScale::AgentConnection, @cookie, @thread_name).
      once.
      and_return(@audit_connection)
    @text = 'some text'
    @auditor = RightScale::AuditStub.instance
    @auditor.init(:listen_port => port, :cookie => @cookie, :thread_name => @thread_name)

    # defeat command serializer to make it easier to compare arguments.
    flexmock(::RightScale::CommandSerializer).should_receive(:dump).and_return { |unserialized| unserialized }
  end

  it 'should update status' do
    cmd = { :name => :audit_update_status, :content => @text, :options => {}, :cookie => @cookie, :thread_name => @thread_name }
    @audit_connection.should_receive(:send_data).with(cmd).once.and_return { stop_em_test }
    run_em_test { @auditor.update_status(@text) }
  end

  it 'should create new section' do
    cmd = { :name => :audit_create_new_section, :content => @text, :options => {}, :cookie => @cookie, :thread_name => @thread_name }
    @audit_connection.should_receive(:send_data).with(cmd).once.and_return { stop_em_test }
    run_em_test { @auditor.create_new_section(@text) }
  end

  it 'should append output' do
    cmd = { :name => :audit_append_output, :content => @text, :options => {}, :cookie => @cookie, :thread_name => @thread_name }
    @audit_connection.should_receive(:send_data).with(cmd).once.and_return { stop_em_test }
    run_em_test { @auditor.append_output(@text) }
  end

  it 'should append info' do
    cmd = { :name => :audit_append_info, :content => @text, :options => {}, :cookie => @cookie, :thread_name => @thread_name }
    @audit_connection.should_receive(:send_data).with(cmd).once.and_return { stop_em_test }
    run_em_test { @auditor.append_info(@text) }
  end

  it 'should append error' do
    cmd = { :name => :audit_append_error, :content => @text, :options => {}, :cookie => @cookie, :thread_name => @thread_name }
    @audit_connection.should_receive(:send_data).with(cmd).once.and_return { stop_em_test }
    run_em_test { @auditor.append_error(@text) }
  end

  it 'should stop when timeout expires' do
    cmd = { :name => :close_connection, :cookie => @cookie, :thread_name => @thread_name }
    @audit_connection.should_receive(:send_data).with(cmd).once.and_return(true)
    @audit_connection.should_receive(:close_connection).once.and_return(true)
    stopped = false
    run_em_test { @auditor.stop { stopped = true; stop_em_test } }
    stopped.should be_true
  end

end
