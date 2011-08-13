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

require 'singleton'

module RightScale

  # Provides access to RightLink agent audit methods
  class ExternalParameterGatherer
    include EM::Deferrable

    # Failure title and message if any
    attr_reader :failure_title, :failure_message

    # Initialize parameter gatherer
    #
    # === Parameters
    # bundle<RightScale::ExecutableBundle>:: the bundle for which to gather inputs
    # options[:listen_port]:: Command server listen port
    # options[:cookie]:: Command protocol cookie
    #
    # === Return
    # true:: Always return true
    def initialize(bundle, options)
      @serializer = Serializer.new
      @audit = AuditStub.instance
      @cookie = options[:cookie]
      @listen_port = options[:listen_port]
      @executables_inputs = {}

      bundle.executables.each do |exe|
        externals = exe.external_inputs
        next if externals.nil? || externals.empty?
        @executables_inputs[exe] = externals.dup
      end
    end

    #TODO docs
    def run
      if done?
        #we might not have ANY external parameters!
        report_success
        return true
      end

      @audit.create_new_section('Retrieving credentials')

      #Preflight to check validity of cred objects
      ok = true
      @executables_inputs.each_pair do |exe, inputs|
        inputs.each_pair do |name, location|
          next if location.is_a?(RightScale::SecureDocumentLocation)
          msg = "The provided credential (#{location.class.name}) is incompatible with this version of RightLink"
          report_failure('Cannot process external input', msg)
          ok = false
        end
      end

      return false unless ok

      @executables_inputs.each_pair do |exe, inputs|
        inputs.each_pair do |name, location|
          payload = {
            :ticket => location.ticket,
            :namespace => location.namespace,
            :names => [location.name]
          }
          self.send_idempotent_request('/vault/read_document', payload) do |data|
            handle_response(exe, name, location, data)
          end
        end
      end
    end

    protected

    # Handle a RightNet response to our idempotent request. Could be success, failure or unexpected.
    def handle_response(exe, name, location, response)
      result = @serializer.load(response)

      if result.success?
        #Since we only ask for one credential at a time, we can do this...
        secure_document = result.content.first
        if secure_document.envelope_mime_type.nil?
          @executables_inputs[exe][name] = secure_document
          @audit.append_info("Got #{name} of '#{exe.nickname}'; #{count_remaining} remain.")
          if done?
            @audit.append_info("All credential values have been retrieved and processed.")
            report_success
          end
        else
          # The call succeeded but we can't process the credential value
          msg = "The #{name} input of '#{exe.nickname}' was retrieved from the external source, but its type " +
                "(#{secure_document.envelope_mime_type}) is incompatible with this version of RightLink."
          report_failure('Cannot process credential', msg)
        end
      else # We got a result, but it was a failure...
        msg = "Could not retrieve the value of the #{name} input of '#{exe.nickname}' " +
              "from the external source. Reason for failure: #{result.content}."
        report_failure('Failed to retrieve credential', msg)
      end
    rescue Exception => e
      msg = "An unexpected error occurred while retrieving the value of the #{name} input of '#{exe.nickname}.'"
      report_failure('Unexpected error while retrieving credentials', msg, e)
    end

    # Return the number of credentials remaining to be gathered
    def count_remaining
      count = @executables_inputs.values.map { |a| a.values.count { |p| not p.is_a?(RightScale::SecureDocument) } }
      return count.inject { |sum,x| sum + x } || 0
    end

    # Sugar for count_remaining == 0
    def done?
      count_remaining == 0
    end

    # Do the actual substitution of credential values into the bundle
    def substitute_parameters
      @executables_inputs.each_pair do |exe, inputs|
        inputs.each_pair do |name, value|
          case exe
            when RightScale::RecipeInstantiation
              exe.attributes[name] = value.content
            when RightScale::RightScriptInstantiation
              exe.parameters[name] = value.content
          end
        end
      end
    end

    # Report the completion of a successful run by updating our Deferrable disposition.
    def report_success
      substitute_parameters
      EM.next_tick { succeed }
    end

    # Report a failure by setting some attributes that our caller will query, then updating our Deferrable
    # disposition so our caller gets notified via errback.
    def report_failure(title, message, exception=nil)
      if exception
        RightLinkLog.error("ExternalParameterGatherer failed due to " +
                           "#{exception.class.name}: #{exception.message} (#{exception.backtrace.first})")
      end

      @failure_title   = title
      @failure_message = message
      EM.next_tick { fail }
    end

    # Use the command protocol to send an idempotent request. This class cannot reuse Cook's
    # implementation of the command-proto request wrappers because we must gather credentials
    # concurrently for performance reasons. The easiest way to do this is simply to open a
    # new command proto socket for every distinct request we make.
    def send_idempotent_request(operation, payload, options={}, &callback)
      connection = EM.connect('127.0.0.1', @listen_port, AgentConnection, @cookie, callback)
      EM.next_tick do
        connection.send_command(:name => :send_idempotent_request, :type => operation,
                                :payload => payload, :options => options)
      end
    end

  end

end
