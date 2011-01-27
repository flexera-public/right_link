#
# Copyright (c) 2009 RightScale Inc
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
require File.join(File.dirname(__FILE__), '..', 'lib', 'instance_services')

describe InstanceServices do

  include RightScale::SpecHelpers

  before(:each) do
    @audit_proxy = flexmock('AuditProxy')
    flexmock(RightScale::AuditProxy).should_receive(:create).and_yield(@audit_proxy)
    @audit_proxy.should_receive(:create_new_section).by_default
    @audit_proxy.should_receive(:append_info).by_default

    @mgr = RightScale::LoginManager.instance
    @policy = RightScale::LoginPolicy.new
    @services = InstanceServices.new('bogus_agent_id')

    #update_login_policy should audit its execution
    flexmock(@services).should_receive(:send_retryable_request).
            with('/auditor/create_entry', Hash, Proc).
            and_yield(RightScale::ResultsMock.new.success_results('bogus_content'))
  end

  it 'should update login policy' do
    flexmock(@mgr).should_receive(:update_policy).with(@policy).and_return(true)

    @services.update_login_policy(@policy)
  end

  it 'should audit failures when they occur' do
    error = "I'm sorry Dave, I can't do that."
    @audit_proxy.should_receive(:append_error).with(/#{error}/, Hash)
    flexmock(@mgr).should_receive(:update_policy).with(@policy).and_raise(Exception.new(error))
  end
end
