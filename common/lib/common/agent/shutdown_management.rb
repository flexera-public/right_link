#
# Copyright (c) 2011 RightScale Inc
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

module RightScale

  module ShutdownManagement

    # initial level; no shutdown requested.
    CONTINUE = 'continue'

    # requested a reboot.
    REBOOT = 'reboot'

    # requested a stop (keep boot volume after shutdown).
    STOP = 'stop'

    # requested a terminate (discard boot volume after shutdown).
    TERMINATE = 'terminate'

    # states.
    LEVELS = [CONTINUE, REBOOT, STOP, TERMINATE]

    # invalid level exception.
    class InvalidLevel < Exception; end

    # Represents outstanding request(s) for reboot, stop or terminate instance.
    # Requests are cumulative and implicitly non-decreasing in level (e.g. reboot
    # never superceeds terminate).
    class ShutdownRequest

      def initialize
        @level = CONTINUE
        @immediate = false
      end

      # true if no shutdown was requested, false if shutdown was requested.
      def continue?; CONTINUE == level; end

      # true if any requested shutdown will interrupt sequence of running scripts
      # immediately (current script is allowed to complete).
      # false to defer shutdown until all outstanding scripts have run.
      def immediately?; @immediately; end
      def immediately!
        raise InvalidLevel.new("Invalid shutdown level for requesting immediately: #{@level.inspect}") if continue?
        @immediately = true
      end

      # Normalizes and validates shutdown level.
      def level; @level; end
      def level=(value)
        value = value.to_s
        raise InvalidLevel.new("Invalid shutdown level: #{value.inspect}") unless LEVELS.include?(value)

        # strictly escalate to higher level and ignore lower level requests.
        @level = value if LEVELS.index(value) > LEVELS.index(@level)
        @level
      end

    end  # ShutdownRequest

    # Mixin for managing shutdown requests.
    module Helpers

      protected

      # gets shared instance shutdown request state.
      def shutdown_request
        InstanceState.shutdown_request
      end

      # Manages shutdown requests by communicating the need to shutdown an
      # instance with the core agent, if necessary.
      #
      # === Parameters
      # audit(Audit):: audit for shutdown action, if needed.
      #
      # === Block
      # block(Proc):: continuation block for successful handling of shutdown or nil
      #
      # === Return
      # always true
      def manage_shutdown_request(audit)
        request = shutdown_request
        case level = request.level
        when CONTINUE
          yield if block_given?
          return true
        when REBOOT
          operation = "/forwarder/reboot"
          payload = {:agent_identity => @agent_identity}
        when STOP, TERMINATE
          operation = "/forwarder/soft_decommission"
          payload = {:agent_identity => @agent_identity,
                     :audit_id => audit.id,
                     :skip_db_update => false,
                     :kind => level}
        else
          raise InvalidLevel.new("Unexpected shutdown level: #{level.inspect}")
        end

        # request shutdown (kind indicated by operation and/or payload).
        audit.update_status("Requesting remote #{level} instance.")
        send_retryable_request(operation, payload) do |r|
          res = result_from(r)
          if res.success?
            yield if block_given?
          else
            handle_failed_shutdown_request(audit, "Failed to remotely #{level} instance", res)
          end
        end
        true
      rescue Exception => e
        handle_failed_shutdown_request(audit, e)
      end

      # Handles any shutdown failure.
      #
      # === Parameters
      # msg(String):: Error message that will be audited and logged
      # res(RightScale::OperationResult):: Operation result with additional information
      #
      # === Return
      # always true
      def handle_failed_shutdown_request(audit, msg, res = nil)

        if msg.kind_of?(Exception)
          e = msg
          detailed = "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
          msg = e.message
        else
          detailed = nil
        end
        msg += ": #{res.content}" if res && res.content
        audit.append_error(msg, :category => RightScale::EventCategories::CATEGORY_ERROR)
        log_error(detailed) if detailed
        true
      end

    end  # Helpers

  end  # ShutdownManagement

end  # RightScale
