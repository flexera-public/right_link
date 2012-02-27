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

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'instance'))

shared_examples_for 'mocks cook' do

  module RightScale
    class MockCook

      attr_accessor :mock_attributes

      def initialize
        @mock_attributes = {:thread_name => ::RightScale::AgentConfig.default_thread_name}
      end

      def has_default_thread?
        ::RightScale::AgentConfig.default_thread_name == @mock_attributes[:thread_name]
      end

    end
  end

  require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'instance', 'cook'))

  before(:each) do
    @mock_cook = flexmock(::RightScale::MockCook.new)
    flexmock(::RightScale::Cook).should_receive(:instance).and_return(@mock_cook)
  end

end  # 'mocks cook'
