#
# Copyright (c) 2012 RightScale Inc
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

describe RightScale::MessageEncoder do
  include RightScale::SpecHelper

  let(:agent_identity) { 'rs-instance-1-1' }
  let(:object_data)    { RightScale::ExecutableBundle.new }
  let(:raw_data)       { ["ABC" * 11, "DEF" * 5] }

  before do
    setup_state(agent_identity)
  end

  shared_examples_for 'encoder' do
    it { should respond_to :dump }
    it { should respond_to :load }

    it "should encode data" do
      subject.dump(data).should_not == data
    end

    it "should be able to decode data" do
      subject.load(subject.dump(data)).should == data
    end
  end

  context "secret encoder" do
    subject { RightScale::MessageEncoder::SecretSerializer.new(agent_identity, 'my secret') }
    context "packet data" do
      let(:data) { object_data }
      it_should_behave_like 'encoder'
    end
    context "raw data" do
      let(:data) { raw_data }
      it_should_behave_like 'encoder'
    end
  end
end
