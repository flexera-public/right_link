#
# Copyright (c) 2010-2011 RightScale Inc
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

describe RightScale::BundleQueue do

  include RightScale::SpecHelper

  it_should_behave_like 'mocks shutdown request'

  before(:each) do
    @mutex = Mutex.new
    @queue_closed = false
    @audit = flexmock('audit')
    @audit.should_receive(:update_status).and_return(true)
    @contexts = []
    @sequences = {}
    @required_completion_order = {}
    @run_sequence_names = {}
    @multi_threaded = false
  end

  after(:each) do
    ::RightScale::Log.has_errors?.should be_false
  end

  shared_examples_for 'a bundle queue' do

    # Mocks thread queues and the supporting object graph.
    #
    # === Parameters
    # options[:count](Fixnum):: number of sequences to mock
    # options[:decommission](Boolean):: true for decommission bundle
    #
    # === Block
    # yields sequence index and must return a unique [sequence_name, thread_name] pair or else a single value for both
    #
    # === Return
    # true: always true
    def mock_sequence(options = { :count => 1, :decommission => false })
      names = []
      count = options[:count] || 1
      decommission = options[:decommission] || false
      thread_name = nil
      count.times do |sequence_index|
        name_pair = yield(sequence_index)  # require thread_name, sequence_name from caller
        if name_pair.kind_of?(Array)
          thread_name ||= name_pair.first
          sequence_name = name_pair.last
        else
          thread_name ||= ::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME
          sequence_name = name_pair.to_s
        end
        names << sequence_name
        sequence_callback = nil
        bundle = flexmock("bundle #{sequence_name}", :name => sequence_name, :thread_name => thread_name)
        bundle.should_receive(:to_json).and_return("[\"some json\"]")
        context = flexmock("context #{sequence_name}",
                           :audit => @audit,
                           :payload => bundle,
                           :decommission => decommission,
                           :succeeded => true,
                           :thread_name => thread_name,
                           :sequence_name => sequence_name)
        @contexts << context
        sequence = flexmock("sequence #{sequence_name}", :context => context)
        sequence.should_receive(:callback).and_return { |callback| sequence_callback = callback; true }
        sequence.should_receive(:errback).and_return(true)
        sequence.should_receive(:run).and_return do
          done = false
          begin
            @mutex.synchronize do
              # note that the sequence die timer nils the required completion
              # order to make threads go away (before the overall timeout fires)
              done = @required_completion_order.nil? || @required_completion_order[thread_name].first == sequence_name
              if done && @required_completion_order
                @run_sequence_names[thread_name] ||= []
                @run_sequence_names[thread_name] << sequence_name
                @required_completion_order[thread_name].shift
                @required_completion_order.delete(thread_name) if @required_completion_order[thread_name].empty?
              end
            end
            sleep 0.1  # force each queue to yield CPU to exercize internal synchronization
          end until done
          sequence_callback.call
        end
        @sequences[thread_name] ||= {}
        @sequences[thread_name][sequence_name] = sequence
      end

      # require that queued sequences complete in a known order.
      @required_completion_order[thread_name] ||= []
      @required_completion_order[thread_name] += names
    end

    def add_sequence_die_timer
      # run_em_test timeout is 5
      EM.add_timer(4.5) { @mutex.synchronize { @required_completion_order = nil } }
    end

    it 'should default to non active' do
      mock_sequence { 'never run by inactive queue' }
      # ensure inactive queue doesn't leak bundle queue stuff to EM
      run_em_test do
        @queue.push(@contexts.shift)
        EM.add_timer(0.2) { EM.stop }
      end
      @queue.active?.should be_false
      @queue_closed.should be_false
      @run_sequence_names.empty?.should be_true
      @required_completion_order.should == { ::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME => ['never run by inactive queue'] }
    end

    it 'should run all bundles once active' do
      # enough sequences/threads to make it interesting.
      4.times do |thread_index|
        mock_sequence(:count => 4) do |sequence_index|
          [0 == thread_index ? ::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME : "thread #{thread_index}",
           "sequence ##{sequence_index + 1}"]
        end
      end

      # push some contexts pre-activation and the rest post-activation.
      (@contexts.size / 2).times { @queue.push(@contexts.shift) }
      run_em_test do
        add_sequence_die_timer
        @queue.activate
        @contexts.size.times { @queue.push(@contexts.shift) }
        @queue.close
      end
      @queue_closed.should be_true
      @run_sequence_names.values.flatten.size.should == 16
      @required_completion_order.should == {}
    end

    it 'should not be active upon closing' do
      mock_sequence { 'queued before activation' }
      mock_sequence { 'never runs after deactivation' }
      run_em_test do
        add_sequence_die_timer
        @queue.push(@contexts.shift)
        @queue.activate
        @queue.close
        @queue.push(@contexts.shift)
      end
      @queue_closed.should be_true
      @queue.active?.should be_false
      @run_sequence_names.values.flatten.size.should == 1
      @required_completion_order.should == { ::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME => ['never runs after deactivation'] }
    end

    it 'should process the shutdown bundle' do
      # prepare multiple contexts which must finish before decommissioning.
      3.times do |thread_index|
        mock_sequence(:count => 3) do |sequence_index|
          [0 == thread_index ? ::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME : "thread #{thread_index}",
           "sequence ##{sequence_index + 1}"]
        end
      end

      # default thread will be restarted to run decommission bundle after all
      # running threads are closed by shutdown bundle (including default thread).
      count_before_decommission = @contexts.size
      mock_sequence { 'ignored due to decommissioning and not a decommission bundle' }
      mock_sequence(:decommission => true) { 'decommission bundle' }
      mock_sequence { 'never runs after decommission closes queue' }
      @required_completion_order[::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME].delete('ignored due to decommissioning and not a decommission bundle')

      shutdown_processed = false
      flexmock(@mock_shutdown_request).
        should_receive(:process).
        and_return do
          shutdown_processed = true
          @contexts.size.times { @queue.push(@contexts.shift) }
          @queue.close
          true
        end
      flexmock(@mock_shutdown_request).should_receive(:immediately?).and_return { shutdown_processed }
      run_em_test do
        add_sequence_die_timer
        @queue.activate
        count_before_decommission.times { @queue.push(@contexts.shift) }
        @queue.push(::RightScale::MultiThreadBundleQueue::SHUTDOWN_BUNDLE)
      end
      shutdown_processed.should be_true
      @queue_closed.should be_true
      @run_sequence_names.values.flatten.size.should == count_before_decommission + 1
      @run_sequence_names[::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME].last.should == 'decommission bundle'
      @required_completion_order.should == { ::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME => ['never runs after decommission closes queue'] }
    end

  end

  describe RightScale::SingleThreadBundleQueue do

    it_should_behave_like 'a bundle queue'

    before(:each) do
      @queue = RightScale::SingleThreadBundleQueue.new { @queue_closed = true; EM.stop }
      sequences = @sequences
      flexmock(@queue).should_receive(:create_sequence).and_return { |context| sequences[context.thread_name][context.sequence_name] }
    end

  end

  describe RightScale::MultiThreadBundleQueue do

    it_should_behave_like 'a bundle queue'

    before(:each) do
      @queue = RightScale::MultiThreadBundleQueue.new { @queue_closed = true; EM.stop }
      sequences = @sequences
      flexmock(@queue).should_receive(:create_thread_queue).with(String, Proc).and_return do |thread_name, continuation|
        thread_queue = RightScale::SingleThreadBundleQueue.new(thread_name, &continuation)
        flexmock(thread_queue).should_receive(:create_sequence).and_return { |context| sequences[context.thread_name][context.sequence_name] }
        thread_queue
      end
      @multi_threaded = true
    end

  end

end
