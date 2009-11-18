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

class AgentManager

  include Nanite::Actor

  expose :ping, :set_log_level, :execute, :record_fault

  # Valid log levels
  LEVELS = [:debug, :info, :warn, :error, :fatal]

  # Always return success, used for troubleshooting
  #
  # === Return
  # res<RightScale::OperationResult>:: Always returns success
  def ping(_)
    res = RightScale::OperationResult.success
  end

  # Change log level of agent
  #
  # === Parameter
  # level<Symbol>:: One of :debug, :info, :warn, :error, :fatal
  #
  # === Return
  # res<RightScale::OperationResult>:: Success if level was changed, error otherwise
  def set_log_level(level)
    return RightScale::OperationResult.error("Invalid log level '#{level.to_s}'") unless LEVELS.include?(level)
    RightScale::RightLinkLog.level = level
    res = RightScale::OperationResult.success
  end

  # Eval given code in context of agent
  #
  # === Parameter
  # code<String>:: Code to be evaled
  #
  # === Return
  # res<RightScale::OperationResult>:: Success with result if code didn't raise an exception
  #                                    Failure with exception message otherwise
  def execute(code)
    begin
      return RightScale::OperationResult.success(self.instance_eval(code))
    rescue Exception => e
      return RightScale::OperationResult.error(e.message + " at\n" + e.backtrace.join("\n"))
    end
  end

  # Process fault (i.e. mapper failed to decrypt one of our packets)
  # Vote for re-enrollment
  #
  # === Return
  # res<RightScale::OperationResult>:: Always returns success
  def record_fault(_)
    RightScale::ReenrollManager.vote
    res = RightScale::OperationResult.success
  end

  # Process exception raised by handling of packet
  # Check if it's a serialization error and if the packet has a valid signature, if so
  # vote for re-enroll
  #
  # === Parameters
  # e<Exception>:: Exception to be analyzed
  # msg<String>:: Serialized message that triggered error
  #
  # === Return
  # true:: Always return true
  def self.process_exception(e, msg)
    if e.is_a?(Nanite::Serializer::SerializationError)
      begin
        data = JSON.load(msg)
        sig = Nanite::Signature.from_data(data['signature'])
        @cert ||= Nanite::Certificate.load(File.join(RightScale::RightLinkConfig[:certs_dir], 'mapper.cert'))
        ReenrollManager.vote if sig.match?(@cert)
      rescue Exception => _
      end
    end
  end

end
