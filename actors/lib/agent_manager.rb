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

require 'socket'

class AgentManager

  include RightScale::Actor

  expose :ping, :stats, :set_log_level, :execute, :connect, :disconnect, :record_fault

  # Valid log levels
  LEVELS = [:debug, :info, :warn, :error, :fatal]

  # Initialize broker
  #
  # === Parameters
  # agent(RightScale::Agent):: This agent
  def initialize(agent)
    @agent = agent
  end

  # Always return success along with identity, protocol version, and broker information
  # Used for troubleshooting
  #
  # === Return
  # res(RightScale::OperationResult):: Always returns success
  def ping(_)
    res = RightScale::OperationResult.success(:identity => @agent.options[:identity],
                                              :hostname => Socket.gethostname,
                                              :version => RightScale::RightLinkConfig.protocol_version,
                                              :brokers => @agent.broker.status,
                                              :time => Time.now.to_i)
  end

  # Retrieve statistics about agent operation
  #
  # === Parameters:
  # options(Hash):: Request options:
  #   :reset(Boolean):: Whether to reset the statistics after getting the current ones
  #
  # === Return
  # res(RightScale::OperationResult):: Always returns success
  def stats(options)
    res = @agent.stats(RightScale::SerializationHelper.symbolize_keys(options))
  end

  # Change log level of agent
  #
  # === Parameter
  # level(Symbol|String):: One of :debug, :info, :warn, :error, :fatal
  #
  # === Return
  # res(RightScale::OperationResult):: Success if level was changed, error otherwise
  def set_log_level(level)
    level = level.to_sym if level.is_a?(String)
    res = if LEVELS.include?(level)
      RightScale::RightLinkLog.level = level
      RightScale::OperationResult.success
    else
      RightScale::OperationResult.error("Invalid log level '#{level.to_s}'")
    end
  end

  # Eval given code in context of agent
  #
  # === Parameter
  # code(String):: Code to be eval'd
  #
  # === Return
  # res(RightScale::OperationResult):: Success with result if code didn't raise an exception
  #                                    Failure with exception message otherwise
  def execute(code)
    begin
      return RightScale::OperationResult.success(self.instance_eval(code))
    rescue Exception => e
      return RightScale::OperationResult.error(e.message + " at\n" + e.backtrace.join("\n"))
    end
  end

  # Connect agent to an additional broker or reconnect it if connection has failed
  # Assumes agent already has credentials on this broker and identity queue exists
  #
  # === Parameters
  # options(Hash):: Connect options:
  #   :host(String):: Host name of broker
  #   :port(Integer):: Port number of broker
  #   :id(Integer):: Small unique id (aka index) associated with this broker for use in forming alias
  #   :priority(Integer|nil):: Priority position of this broker in list for use
  #     by this agent with nil meaning add to end of list
  #   :force(Boolean):: Reconnect even if already connected
  #
  # === Return
  # res(RightScale::OperationResult):: Success unless exception is raised
  def connect(options)
    options = RightScale::SerializationHelper.symbolize_keys(options)
    res = RightScale::OperationResult.success
    begin
      if error = @agent.connect(options[:host], options[:port], options[:id], options[:priority], options[:force])
        res = RightScale::OperationResult.error(error)
      end
    rescue Exception => e
      res = RightScale::OperationResult.error("Failed to connect to broker: #{e.message}")
    end
    res
  end

  # Disconnect agent from a broker
  #
  # === Parameters
  # options(Hash):: Connect options:
  #   :host(String):: Host name of broker
  #   :port(Integer):: Port number of broker
  #   :remove(Boolean):: Remove broker from configuration in addition to disconnecting it
  #
  # === Return
  # res(RightScale::OperationResult):: Success unless exception is raised
  def disconnect(options)
    options = RightScale::SerializationHelper.symbolize_keys(options)
    res = RightScale::OperationResult.success
    begin
      if error = @agent.disconnect(options[:host], options[:port], options[:remove])
        res = RightScale::OperationResult.error(error)
      end
    rescue Exception => e
      res = RightScale::OperationResult.error("Failed to disconnect from broker: #{e.message}")
    end
    res
  end

  # Declare one or more broker connections unusable because connection setup has failed
  #
  # === Parameters
  # options(Hash):: Failure options:
  #   :brokers(Array):: Identity of brokers
  #
  # === Return
  # res(RightScale::OperationResult):: Success unless exception is raised
  def connect_failed(options)
    options = RightScale::SerializationHelper.symbolize_keys(options)
    res = RightScale::OperationResult.success
    begin
      if error = @agent.connect_failed(options[:brokers])
        res = RightScale::OperationResult.error(error)
      end
    rescue Exception => e
      res = RightScale::OperationResult.error("Failed to notify agent that brokers #{options[:brokers]} are unusable: #{e.message}")
    end
    res
  end

  # Process fault (i.e. mapper failed to decrypt one of our packets)
  # Vote for re-enrollment
  #
  # === Return
  # res(RightScale::OperationResult):: Always returns success
  def record_fault(_)
    RightScale::ReenrollManager.vote
    res = RightScale::OperationResult.success
  end

  # Process exception raised by handling of packet
  # If it's a serialization error and the packet has a valid signature, vote for re-enroll
  #
  # === Parameters
  # e(Exception):: Exception to be analyzed
  # msg(String):: Serialized message that triggered error
  #
  # === Return
  # true:: Always return true
  def self.process_exception(e, msg)
    if e.is_a?(RightScale::Serializer::SerializationError)
      begin
        serializer = Serializer.new
        data = serializer.load(msg)
        sig = RightScale::Signature.from_data(data['signature'])
        @cert ||= RightScale::Certificate.load(File.join(RightScale::RightLinkConfig[:certs_dir], 'mapper.cert'))
        ReenrollManager.vote if sig.match?(@cert)
      rescue Exception => _
        RightScale::RightLinkLog.error("Failed processing serialization error", e)
      end
    end
  end

end
