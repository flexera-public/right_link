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

module RightScale

  # Dispatching of payload to specified actor
  class Dispatcher
    attr_reader :registry, :serializer, :identity, :amq, :options
    attr_accessor :evmclass

    def initialize(amq, registry, serializer, identity, options)
      @amq = amq
      @registry = registry
      @serializer = serializer
      @identity = identity
      @options = options
      @evmclass = EM
      @evmclass.threadpool_size = (@options[:threadpool_size] || 20).to_i
    end

    def dispatch(deliverable)
      prefix, meth = deliverable.type.split('/')[1..-1]
      meth ||= :index
      actor = registry.actor_for(prefix)

      operation = lambda do
        begin
          args = [ deliverable.payload ]
          args.push(deliverable) if actor.method(meth).arity == 2
          actor.send(meth, *args)
        rescue Exception => e
          handle_exception(actor, meth, deliverable, e)
        end
      end
      
      callback = lambda do |r|
        if deliverable.kind_of?(Request)
          r = Result.new(deliverable.token, deliverable.reply_to, r, identity)
          RightLinkLog.info("SEND #{r.to_s([])}")
          amq.queue(deliverable.reply_to, :no_declare => options[:secure]).publish(serializer.dump(r))
        end
        r # For unit tests
      end

      if @options[:single_threaded] || @options[:thread_poolsize] == 1
        @evmclass.next_tick { callback.call(operation.call) }
      else
        @evmclass.defer(operation, callback)
      end
    end

    private

    def describe_error(e)
      "#{e.class.name}: #{e.message}\n #{e.backtrace.join("\n  ")}"
    end

    def handle_exception(actor, meth, deliverable, e)
      error = describe_error(e)
      RightLinkLog.error(error)
      begin
        if actor.class.exception_callback
          case actor.class.exception_callback
          when Symbol, String
            actor.send(actor.class.exception_callback, meth.to_sym, deliverable, e)
          when Proc
            actor.instance_exec(meth.to_sym, deliverable, e, &actor.class.exception_callback)
          end
        end
      rescue Exception => e1
        error = describe_error(e1)
        RightLinkLog.error(error)
      end
      error
    end

  end # Dispatcher
  
end # RightScale
