require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'lib', 'agent_deployer')
require File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'lib', 'agent_controller')

describe AMQP::Client do
  context 'with an incorrect AMQP password' do
    class SUT
      include AMQP::Client

      attr_accessor :reconnecting, :settings, :channels
    end

    before(:each) do
      @sut = SUT.new
      @sut.reconnecting = false
      @sut.settings = {:host=>'testhost', :port=>'12345'}
      @sut.channels = {}

      @sut.should_receive(:initialize)
    end

    context 'and no :retry' do
      it 'should reconnect immediately' do
        EM.should_receive(:reconnect)
        EM.should_receive(:add_timer).never

        @sut.reconnect()
      end
    end

    context 'and a :retry of false' do
      it 'should not schedule a reconnect' do
        @sut.settings[:retry] = false

        EM.should_receive(:reconnect).never
        EM.should_receive(:add_timer).never

        lambda { @sut.reconnect() }.should raise_error(StandardError)
      end
    end

    context 'and a :retry of true' do
      it 'should reconnect immediately' do
        @sut.settings[:retry] = true

        EM.should_receive(:reconnect)
        EM.should_receive(:add_timer).never

        @sut.reconnect()
      end
    end

    context 'and a :retry of 15 seconds' do
      it 'should schedule a reconnect attempt in 15s' do
        @sut.settings[:retry] = 15

        EM.should_receive(:reconnect).never
        EM.should_receive(:add_timer).with(15)

        @sut.reconnect()
      end
    end

    context 'and a :retry containing a Proc that returns 30' do
      it 'should schedule a reconnect attempt in 30s' do
        @sut.settings[:retry] = Proc.new {30}

        EM.should_receive(:reconnect).never
        EM.should_receive(:add_timer).with(30)

        @sut.reconnect()
      end
    end

  end

end
