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

require 'rubygems'
require File.join(File.dirname(__FILE__), 'stats_helper')

class MQ
  class Queue
    # Asks the broker to redeliver all unacknowledged messages on a
    # specified channel. Zero or more messages may be redelivered.
    #
    # * requeue (default false)
    # If this parameter is false, the message will be redelivered to the original recipient.
    # If this flag is true, the server will attempt to requeue the message, potentially then
    # delivering it to an alternative subscriber.
    #
    def recover(requeue = false)
      @mq.callback{
        @mq.send Protocol::Basic::Recover.new({ :requeue => requeue })
      }
      self
    end
  end

  # May raise a MQ::Error exception when the frame payload contains a
  # Protocol::Channel::Close object.
  #
  # This usually occurs when a client attempts to perform an illegal
  # operation. A short, and incomplete, list of potential illegal operations
  # follows:
  # * publish a message to a deleted exchange (NOT_FOUND)
  # * declare an exchange using the reserved 'amq.' naming structure (ACCESS_REFUSED)
  #
  def process_frame frame
    log :received, frame

    case frame
    when Frame::Header
      @header = frame.payload
      @body = ''

    when Frame::Body
      @body << frame.payload
      if @body.length >= @header.size
        if @method.is_a? Protocol::Basic::Return
          @on_return_message.call @method, @body if @on_return_message
        else
          @header.properties.update(@method.arguments)
          @consumer.receive @header, @body if @consumer
        end
        @body = @header = @consumer = @method = nil
      end

    when Frame::Method
      case method = frame.payload
      when Protocol::Channel::OpenOk
        send Protocol::Access::Request.new(:realm => '/data',
                                           :read => true,
                                           :write => true,
                                           :active => true,
                                           :passive => true)

      when Protocol::Access::RequestOk
        @ticket = method.ticket
        callback{
          send Protocol::Channel::Close.new(:reply_code => 200,
                                            :reply_text => 'bye',
                                            :method_id => 0,
                                            :class_id => 0)
        } if @closing
        succeed

      when Protocol::Basic::CancelOk
        if @consumer = consumers[ method.consumer_tag ]
          @consumer.cancelled
        else
          MQ.error "Basic.CancelOk for invalid consumer tag: #{method.consumer_tag}"
        end

      when Protocol::Queue::DeclareOk
        queues[ method.queue ].receive_status method

      when Protocol::Basic::Deliver, Protocol::Basic::GetOk
        @method = method
        @header = nil
        @body = ''

        if method.is_a? Protocol::Basic::GetOk
          @consumer = get_queue{|q| q.shift }
          MQ.error "No pending Basic.GetOk requests" unless @consumer
        else
          @consumer = consumers[ method.consumer_tag ]
          MQ.error "Basic.Deliver for invalid consumer tag: #{method.consumer_tag}" unless @consumer
        end

      when Protocol::Basic::GetEmpty
        if @consumer = get_queue{|q| q.shift }
          @consumer.receive nil, nil
        else
          MQ.error "Basic.GetEmpty for invalid consumer"
        end

      when Protocol::Basic::Return
        @method = method
        @header = nil
        @body = ''

      when Protocol::Channel::Close
        raise Error, "#{method.reply_text} in #{Protocol.classes[method.class_id].methods[method.method_id]} on #{@channel}"

      when Protocol::Channel::CloseOk
        @closing = false
        conn.callback{ |c|
          c.channels.delete @channel
          c.close if c.channels.empty?
        }

      when Protocol::Basic::ConsumeOk
        if @consumer = consumers[ method.consumer_tag ]
          @consumer.confirm_subscribe
        else
          MQ.error "Basic.ConsumeOk for invalid consumer tag: #{method.consumer_tag}"
        end
      end
    end
  end

  # Provide callback to be activated when a message is returned
  def return_message(&blk)
    @on_return_message = blk
  end

end

# monkey patch to the amqp gem that adds :no_declare => true option for new Queue objects.
# This allows an instance that has no configuration privileges to enroll without blowing
# up the AMQP gem when it tries to subscribe to its queue before it has been created.
# Exchange :no_declare support is already in the eventmachine-0.12.10 gem.
# temporary until we get this into amqp proper
MQ::Queue.class_eval do
  def initialize mq, name, opts = {}
    @mq = mq
    @opts = opts
    @bindings ||= {}
    @mq.queues[@name = name] ||= self
    unless opts[:no_declare]
      @mq.callback{
        @mq.send AMQP::Protocol::Queue::Declare.new({ :queue => name,
                                                      :nowait => true }.merge(opts))
      }
    end
  end
end

begin
  # Monkey patch AMQP reconnect backoff
  require 'amqp'

  AMQP::Client.module_eval do
    def initialize opts = {}
      @settings = opts
      extend AMQP.client

      @on_disconnect ||= proc{ @connection_status.call(:failed) if @connection_status }

      timeout @settings[:timeout] if @settings[:timeout]
      errback{ @on_disconnect.call } unless @reconnecting

      @connected = false
    end

    def reconnect(force = false)
      if @reconnecting and not force
        # Wait after first reconnect attempt and in between each subsequent attempt
        EM.add_timer(@settings[:reconnect_interval] || 5) { reconnect(true) }
        return
      end

      unless @reconnecting
        @deferred_status = nil
        initialize(@settings)

        mqs = @channels
        @channels = {}
        mqs.each{ |_,mq| mq.reset } if mqs

        @reconnecting = true

        again = @settings[:reconnect_delay]
        again = again.call if again.is_a?(Proc)
        if again.is_a?(Numeric)
          # Wait before making initial reconnect attempt
          EM.add_timer(again) { reconnect(true) }
          return
        elsif ![nil, true].include?(again)
          raise ::AMQP::Error, "Could not interpret :reconnect_delay => #{again.inspect}; expected nil, true, or Numeric"
        end
      end

      RightScale::RightLinkLog.warning("Attempting to reconnect to broker " +
        "#{RightScale::AgentIdentity.new('rs', 'broker', @settings[:port].to_i, @settings[:host].gsub('-', '~')).to_s}")
      log 'reconnecting'
      EM.reconnect(@settings[:host], @settings[:port], self)
    end
  end

  # Monkey patch AMQP to clean up @conn when an error is raised after a broker request failure,
  # otherwise AMQP becomes unusable
  AMQP.module_eval do
    def self.start *args, &blk
      begin
        EM.run{
          @conn ||= connect *args
          @conn.callback(&blk) if blk
          @conn
        }
      rescue Exception => e
        @conn = nil
        raise e
      end
    end
  end

  # This monkey patch catches exceptions that would otherwise cause EM to stop or be in a bad
  # state if a top level EM error handler was setup. Instead close the connection and leave EM
  # alone.
  # Don't log an error if the environment variable IGNORE_AMQP_FAILURES is set (used in the 
  # enroll script)
  AMQP::Client.module_eval do
    alias :orig_receive_data :receive_data
    def receive_data(*args)
      begin
        orig_receive_data(*args)
      rescue Exception => e
        RightScale::RightLinkLog.error("Exception caught while processing AMQP frame, closing connection",
                                       e, :trace) unless ENV['IGNORE_AMQP_FAILURES']
        close_connection
      end
    end
  end

  # Add a new callback to amqp gem that triggers once the handshake with the broker completed
  # The 'connected' status callback happens before the handshake is done and if it results in
  # a lot of activity it might prevent EM from being able to call the code handling the
  # incoming handshake packet in a timely fashion causing the broker to close the connection
  AMQP::BasicClient.module_eval do
    alias :orig_process_frame :process_frame
    def process_frame(frame)
      orig_process_frame(frame)
      @connection_status.call(:ready) if @connection_status && frame.payload.is_a?(AMQP::Protocol::Connection::Start)
    end
  end

rescue LoadError => e
  # Make sure we're dealing with a legitimate missing-file LoadError
  raise e unless e.message =~ /^no such file to load/
  # Missing 'amqp' indicates that the AMQP gem is not installed; we can ignore this
end

