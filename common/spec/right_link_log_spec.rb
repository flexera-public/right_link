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

describe RightScale::RightLinkLog do

  # Count number of lines logged with the specified text
  # Search is case sensitive and regular expression sensitive
  #
  # === Parameters
  # text(String):: Text to search for
  #
  # === Return
  # (Integer):: Number of lines where text found
  def log_count(text)
    # no such animal as egrep in windows, so hacked up an equivalent here.
    pattern = Regexp.compile(text)
    File.read(@log_file).each.select { |x| x =~ pattern }.count
  end

  before(:all) do
    ENV['RS_LOG'] = 'true'
  end

  before(:each) do
    Singleton.__init__(RightScale::RightLinkLog)
  end

  after(:all) do
    Singleton.__init__(RightScale::RightLinkLog)
    ENV['RS_LOG'] = nil
  end

  it 'should set default level to info' do
    RightScale::RightLinkLog.level.should == :info
  end

  it 'should change level to debug when force_debug' do
    RightScale::RightLinkLog.level.should == :info
    RightScale::RightLinkLog.force_debug
    RightScale::RightLinkLog.level.should == :debug
  end

  context "logging" do

    before(:each) do
      # note that log directory doesn't necessarily exist in Windows dev/test
      # environment.
      log_dir = RightScale::RightLinkConfig[:platform].filesystem.log_dir
      FileUtils.mkdir_p(log_dir) unless File.directory?(log_dir)

      # use a unique name for the test because the file cannot be deleted after
      # the test in the Windows case (until the process exits) and we need to
      # avoid any potential conflicts with other tests, etc.
      @log_name = "right_link_log_test-9D9A9CB7-24A1-4093-9F75-D462D373A0D8"
      @log_file = File.join(log_dir, "#{@log_name}.log")
      RightScale::RightLinkLog.program_name = "tester"
      RightScale::RightLinkLog.log_to_file_only(true)
      RightScale::RightLinkLog.init(@log_name, log_dir)
    end

    after(:each) do
      # note that the log is held open in the Windows case by RightLinkLog so we
      # cannot delete it after each test. on the other hand, we can truncate the
      # log to zero size and continue to the next test (ultimately leaving an
      # empty file after the test, which is acceptable).
      File.delete(@log_file) if File.file?(@log_file) rescue File.truncate(@log_file, 0)
    end

    it 'should log info but not debug by default' do
      RightScale::RightLinkLog.debug("Test debug")
      RightScale::RightLinkLog.info("Test info")
      log_count("Test debug$").should == 0
      log_count("Test info$").should == 1
    end

    it 'should log debug after adjust level to :debug' do
      RightScale::RightLinkLog.level = :debug
      RightScale::RightLinkLog.debug("Test debug")
      RightScale::RightLinkLog.info("Test info")
      log_count("Test debug$").should == 1
      log_count("Test info$").should == 1
    end

    it 'should log additional error string when given' do
      RightScale::RightLinkLog.warning("Test warning", "Error")
      RightScale::RightLinkLog.error("Test error", "Error")
      log_count("Test warning \\\(Error\\\)$").should == 1
      log_count("Test error \\\(Error\\\)$").should == 1
    end

    it 'should log without exception when none given' do
      begin
        nil + "string"
      rescue Exception => e
        RightScale::RightLinkLog.warning("Test warning")
        RightScale::RightLinkLog.error("Test error")
      end
      log_count("Test warning$").should == 1
      log_count("Test error$").should == 1
    end

    it 'should log with exception class, message, and caller appended by default when exception given' do
      begin
        nil + "string"
      rescue Exception => e
        RightScale::RightLinkLog.warning("Test warning", e)
        RightScale::RightLinkLog.error("Test error", e)
      end
      log_count("Test warning \\\(NoMethodError: undefined method \\\`\\\+\' for nil:NilClass in .*right_link_log_spec.*\\\)$").should == 1
      log_count("Test error \\\(NoMethodError: undefined method \\\`\\\+\' for nil:NilClass in .*right_link_log_spec.*\\\)$").should == 1
    end

    it 'should log with exception class, message, and caller appended when use :caller' do
      begin
        nil + "string"
      rescue Exception => e
        RightScale::RightLinkLog.warning("Test warning", e, :caller)
        RightScale::RightLinkLog.error("Test error", e, :caller)
      end
      log_count("Test warning \\\(NoMethodError: undefined method \\\`\\\+\' for nil:NilClass in .*right_link_log_spec.*\\\)$").should == 1
      log_count("Test error \\\(NoMethodError: undefined method \\\`\\\+\' for nil:NilClass in .*right_link_log_spec.*\\\)$").should == 1
    end

    it 'should log with exception class and message appended when use :no_trace' do
      begin
        nil + "string"
      rescue Exception => e
        RightScale::RightLinkLog.warning("Test warning", e, :no_trace)
        RightScale::RightLinkLog.error("Test error", e, :no_trace)
      end
      log_count("Test warning \\\(NoMethodError: undefined method \\\`\\\+\' for nil:NilClass\\\)$").should == 1
      log_count("Test error \\\(NoMethodError: undefined method \\\`\\\+\' for nil:NilClass\\\)$").should == 1
    end

    it 'should log with exception class, message, and full backtrace appended when use :trace' do
      begin
        nil + "string"
      rescue Exception => e
        RightScale::RightLinkLog.warning("Test warning", e, :trace)
        RightScale::RightLinkLog.error("Test error", e, :trace)
      end
      log_count("Test warning \\\(NoMethodError: undefined method \\\`\\\+\' for nil:NilClass in$").should == 1
      log_count("Test error \\\(NoMethodError: undefined method \\\`\\\+\' for nil:NilClass in$").should == 1
    end

  end

end
