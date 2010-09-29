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

describe RightScale::AgentIdentity do

  it 'should create a token if none is provided' do
    id = RightScale::AgentIdentity.new('prefix', 'agent_name', 1)
    id.token.should_not be_nil
  end

  it 'should create unique tokens' do
    id = RightScale::AgentIdentity.new('prefix', 'agent_name', 1)
    id.token.should_not be_nil
    id2 = RightScale::AgentIdentity.new('prefix', 'agent_name', 1)
    id2.token.should_not be_nil
    id.token.should_not == id2.token
  end

  it 'should use preset tokens' do
    id = RightScale::AgentIdentity.new('prefix', 'agent_name', 1, 'token')
    id.token.should == 'token'
  end

  it 'should serialize' do
    id = RightScale::AgentIdentity.new('prefix', 'agent_name', 1, 'token')
    id2 = RightScale::AgentIdentity.parse(id.to_s)
    id2.prefix.should == id.prefix
    id2.agent_name.should == id.agent_name
    id2.base_id.should == id.base_id
    id2.token.should == id.token
  end

  it 'should validate' do
    id = RightScale::AgentIdentity.new('prefix', 'agent_name', 1, 'token')
    RightScale::AgentIdentity.valid?(id.to_s).should be_true
  end

  it "should treat serialized id with nanite or mapper prefix as valid" do
    RightScale::AgentIdentity.valid?("nanite-prefix-agent_name-token-1").should be_true
    RightScale::AgentIdentity.valid?("mapper-prefix-agent_name-token-1").should be_true
  end

  it "should parse serialized id with nanite or mapper prefix but discard this prefix" do
    RightScale::AgentIdentity.parse("nanite-prefix-agent_name-token-1").to_s.should == "prefix-agent_name-token-1"
    RightScale::AgentIdentity.parse("mapper-prefix-agent_name-token-1").to_s.should == "prefix-agent_name-token-1"
  end

  it 'should prefix with nanite to make backward compatible' do
    id = RightScale::AgentIdentity.new('prefix', 'agent_name', 1, 'token')
    RightScale::AgentIdentity.compatible_serialized(id.to_s, 10).should == "prefix-agent_name-token-1"
    RightScale::AgentIdentity.compatible_serialized(id.to_s, 9).should == "nanite-prefix-agent_name-token-1"
  end

end
