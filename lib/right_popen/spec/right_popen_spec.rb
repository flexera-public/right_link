unless RUBY_PLATFORM =~ /mswin/ # RightScale::popen3 won't work on windows

require File.join(File.dirname(__FILE__), 'spec_helper')
require 'right_popen'

STANDARD_MESSAGE = 'Standard message'
ERROR_MESSAGE    = 'Error message'
EXIT_STATUS      = 146

describe 'RightScale::popen3' do

  def on_read_stdout(data)
    @stdoutput << data
    @combined  << data
  end

  def on_read_stderr(data)
    @stderr    << data
    @combined  << data
  end

  def on_exit(status)
    @done = status
  end

  before(:each) do
    @done      = false
    @stdoutput = ''
    @stderr    = ''
    @combined  = ''
  end

  it 'should redirect output' do
    EM.next_tick do
      RightScale.popen3("#{File.join(File.dirname(__FILE__), 'produce_output')} '#{STANDARD_MESSAGE}' '#{ERROR_MESSAGE}'", self, :on_read_stdout, :on_read_stderr, :on_exit)
    end
    EM.run do
      timer = EM::PeriodicTimer.new(0.1) do
        if @done
          timer.cancel
          @stdoutput.should == STANDARD_MESSAGE + "\n"
          @stderr.should == ERROR_MESSAGE + "\n"
          EM.stop
        end
      end
    end
  end

  it 'should return the right status' do
    EM.next_tick do
      RightScale.popen3("#{File.join(File.dirname(__FILE__), 'produce_status')} #{EXIT_STATUS}", self, nil, nil, :on_exit)
    end
    EM.run do
      timer = EM::PeriodicTimer.new(0.1) do
        if @done
          timer.cancel
          @done.exitstatus.should == EXIT_STATUS
          EM.stop
        end
      end
    end
  end
end

describe 'RightScale::popen25' do
  def on_read_output(data)
    @output << data
  end

  def on_exit(status)
    @done = status
  end

  before(:each) do
    @done      = false
    @output    = ''
  end

  it 'should redirect output' do
    pending "Fix random hang (deadlock?)"
    EM.next_tick do
      RightScale.popen25("#{File.join(File.dirname(__FILE__), 'produce_output')} '#{STANDARD_MESSAGE}' '#{ERROR_MESSAGE}'", self, :on_read_output, :on_exit)
    end
    EM.run do
      timer = EM::PeriodicTimer.new(0.1) do
        if @done
          timer.cancel
          @output.should == STANDARD_MESSAGE + "\n" + ERROR_MESSAGE + "\n"
          EM.stop
        end
      end
    end
  end

  it 'should return the right status' do
    pending "Fix random hang (deadlock?)"
    EM.next_tick do
      RightScale.popen25("#{File.join(File.dirname(__FILE__), 'produce_status')} #{EXIT_STATUS}", self, nil, :on_exit)
    end
    EM.run do
      timer = EM::PeriodicTimer.new(0.1) do
        if @done
          timer.cancel
          @done.exitstatus.should == EXIT_STATUS
          EM.stop
        end
      end
    end
  end

  it 'should preserve the time ordering of stdout and stderr' do
    pending "Fix random hang (deadlock?)"
    EM.next_tick do
      RightScale.popen25("#{File.join(File.dirname(__FILE__), 'produce_mixed_output')} '#{STANDARD_MESSAGE}' '#{ERROR_MESSAGE}'", self, :on_read_output, :on_exit)
    end
    EM.run do
      timer = EM::PeriodicTimer.new(0.1) do
        if @done
          timer.cancel
          @output.should == ([STANDARD_MESSAGE, ERROR_MESSAGE] * 10).join("\n") + "\n"
          EM.stop
        end
      end
    end
  end
end

end # unless windows
