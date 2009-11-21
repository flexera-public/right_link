require File.join(File.dirname(__FILE__), 'spec_helper')
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'config', 'right_link_config'))
require 'right_popen'

RUBY_CMD         = RightScale::RightLinkConfig[:sandbox_ruby_cmd]
STANDARD_MESSAGE = 'Standard message'
ERROR_MESSAGE    = 'Error message'
EXIT_STATUS      = 146

describe 'RightScale::popen3' do

  def on_read_stdout(data)
    @stdoutput << data
  end

  def on_read_stderr(data)
    @stderr << data
  end

  def on_exit(status)
    @done = status
  end

  before(:each) do
    @done      = false
    @stdoutput = ''
    @stderr    = ''
  end

  it 'should redirect output' do
    EM.next_tick do
      cmd = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_output.rb'))}\" \"#{STANDARD_MESSAGE}\" \"#{ERROR_MESSAGE}\""
      RightScale.popen3(cmd, self, :on_read_stdout, :on_read_stderr, :on_exit)
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
      cmd = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_status.rb'))}\" #{EXIT_STATUS}"
      RightScale.popen3(cmd, self, nil, nil, :on_exit)
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

  it 'should preserve the integrity of stdout and stderr despite interleaving' do
    # manually bump count up for more aggressive multi-threaded testing, lessen
    # for a quick smoke test
    count = 30
    EM.next_tick do
      cmd = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_mixed_output.rb'))}\" #{count}"
      RightScale.popen3(cmd, self, :on_read_stdout, :on_read_stderr, :on_exit)
    end
    EM.run do
      timer = EM::PeriodicTimer.new(0.1) do
        if @done
          timer.cancel
          results = []
          count.times do |i|
            results << "stdout #{i}"
          end
          @stdoutput.should == results.join("\n") + "\n"
          results = []
          count.times do |i|
            (results << "stderr #{i}") if 0 == i % 10
          end
          @stderr.should == results.join("\n") + "\n"
          results = []
          @done.exitstatus.should == 99
          EM.stop
        end
      end
    end
  end

end
