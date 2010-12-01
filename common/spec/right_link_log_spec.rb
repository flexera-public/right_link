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
    `egrep "#{text}" #{@log_file} | wc -l`.to_i
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
      @log_name = "test"
      @log_file = File.join(RightScale::RightLinkConfig[:platform].filesystem.log_dir, "#{@log_name}.log")
      RightScale::RightLinkLog.program_name = "tester"
      RightScale::RightLinkLog.log_to_file_only(true)
      RightScale::RightLinkLog.init(@log_name, RightScale::RightLinkConfig[:platform].filesystem.log_dir)
    end

    after(:each) do
      File.delete(@log_file) if File.file?(@log_file)
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
