#--
# Copyright: Copyright (c) 2010 RightScale, Inc.
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
require 'tmpdir'

describe RightScale::ExecutableSequence do
  include RightScale::SpecHelpers

  SERVER = "repose9.rightscale.com"
  before(:all) do
    setup_state
  end

  after(:all) do
    cleanup_state
  end

  before(:each) do
    @old_cache_path = RightScale::InstanceConfiguration::CACHE_PATH
    @temp_cache_path = Dir.mktmpdir
    RightScale::InstanceConfiguration.const_set(:CACHE_PATH, @temp_cache_path)
  end

  after(:each) do
    RightScale::InstanceConfiguration.const_set(:CACHE_PATH, @old_cache_path)
    FileUtils.remove_entry_secure(@temp_cache_path)
  end

  it 'should start with an empty bundle' do
    @bundle = RightScale::ExecutableBundle.new([], [], 2, nil, [], [])
    @sequence = RightScale::ExecutableSequence.new(@bundle)
  end

  it 'should look up repose servers' do
    @bundle = RightScale::ExecutableBundle.new([], [], 2, nil, [], [SERVER])
    @sequence = RightScale::ExecutableSequence.new(@bundle)
    @sequence.instance_variable_get(:@repose_ips).should_not be_empty
    hostmap = @sequence.instance_variable_get(:@repose_hostnames)
    @sequence.instance_variable_get(:@repose_ips).each {|ip|
      hostmap[ip].should == SERVER
    }
  end

  it 'should fail to request a cookbook we can\'t access' do
    auditor = flexmock(RightScale::AuditStub.instance)
    auditor.should_receive(:create_new_section).with("Retrieving cookbooks").once
    auditor.should_receive(:append_info).with(/Starting at/).once
    auditor.should_receive(:append_info).with("Requesting nonexistent cookbook").once
    auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
    # prevent Chef logging reaching the console during spec test.
    logger = flexmock(::RightScale::RightLinkLog)
    logger.should_receive(:info).with(/Connecting to cookbook server/)
    logger.should_receive(:info).with(/Opening new HTTPS connection to/)
    logger.should_receive(:info).with("Requesting Cookbook nonexistent cookbook:4cdae6d5f1bc33d8713b341578b942d42ed5817f").once
    logger.should_receive(:info).with("Request failed - Net::HTTPForbidden - give up").once

    cookbook = RightScale::Cookbook.new("4cdae6d5f1bc33d8713b341578b942d42ed5817f", "not-a-token",
                                        "nonexistent cookbook")
    position = RightScale::CookbookPosition.new("foo/bar", cookbook)
    sequence = RightScale::CookbookSequence.new(['foo'], [position])
    @bundle = RightScale::ExecutableBundle.new([], [], 2, nil, [sequence],
                                               [SERVER])
    @sequence = RightScale::ExecutableSequence.new(@bundle)
    @sequence.send(:download_repos)
    @sequence.instance_variable_get(:@ok).should be_false
    @sequence.failure_title.should == "Failed to download cookbook"
  end
end
