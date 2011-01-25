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

require File.join(File.dirname(__FILE__), 'spec_helper')
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib',
                                   'payload_types', 'right_script_attachment'))

module RightScale
  describe RightScriptAttachment do
    context 'as a class' do
      it 'should compute a simple hash correctly' do
        RightScriptAttachment.hash_for('http://foo.bar.baz/', 'index.html', 'bsthl').should ==
          Digest::SHA1.hexdigest("http://foo.bar.baz/\000bsthl")
      end

      it 'should compute a hash with a query term correctly' do
        RightScriptAttachment.hash_for('http://foo.bar.baz/?q=bar;baz=foo', 'index.html', 'bsthl').should ==
          Digest::SHA1.hexdigest("http://foo.bar.baz/\000bsthl")
      end
    end

    context 'as an instance' do
      it 'should compute a simple hash correctly' do
        RightScriptAttachment.new('http://foo.bar.baz/', 'index.html', 'bsthl').to_hash.should ==
          Digest::SHA1.hexdigest("http://foo.bar.baz/\000bsthl")
      end

      it 'should compute a hash with a query term correctly' do
        RightScriptAttachment.new('http://foo.bar.baz/?q=bar;baz=foo', 'index.html', 'bsthl').to_hash.should ==
          Digest::SHA1.hexdigest("http://foo.bar.baz/\000bsthl")
      end

      it 'should know how to fill out a session' do
        attachment = RightScriptAttachment.new('http://foo.bar.baz/', 'index.html', 'bsthl')
        session = flexmock('session')
        session.should_receive(:[]=).with('scope', 'attachments').once
        session.should_receive(:[]=).with('resource', attachment.to_hash).once
        session.should_receive(:[]=).with('url', 'http://foo.bar.baz/').once
        session.should_receive(:[]=).with('etag', 'bsthl').once
        session.should_receive(:to_s).and_return("blah").once
        attachment.fill_out(session)
        attachment.token.should == "blah"
      end
    end
  end
end
