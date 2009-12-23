module Nanite
  class Cluster
    attr_reader :agent_timeout, :nanites, :reaper, :serializer, :identity, :amq, :redis, :mapper, :callbacks

    def initialize(amq, agent_timeout, identity, serializer, mapper, state_configuration=nil, tag_store=nil, callbacks = {})
      @amq = amq
      @agent_timeout = agent_timeout
      @identity = identity
      @serializer = serializer
      @mapper = mapper
      @state = state_configuration
      @tag_store = tag_store
      @security = SecurityProvider.get
      @callbacks = callbacks
      setup_state
      @reaper = Reaper.new(agent_timeout)
      setup_queues
    end

    # determine which nanites should receive the given request
    def targets_for(request, include_timed_out)
      return [request.target] if request.target
      __send__(request.selector, request, include_timed_out)
    end

    # adds nanite to nanites map: key is nanite's identity
    # and value is a services/status pair implemented
    # as a hash
    def register(reg)
      case reg
      when Register
        if @security.authorize_registration(reg)
          Nanite::Log.info("RECV #{reg.to_s}")
          nanites[reg.identity] = { :services => reg.services, :status => reg.status, :tags => reg.tags, :timestamp => Time.now.utc.to_i }
          reaper.register(reg.identity, agent_timeout + 1) { nanite_timed_out(reg.identity) }
          callbacks[:register].call(reg.identity, mapper) if callbacks[:register]
        else
          Nanite::Log.warn("RECV NOT AUTHORIZED #{reg.to_s}")
        end
      when UnRegister
        Nanite::Log.info("RECV #{reg.to_s}")
        reaper.unregister(reg.identity)
        nanites.delete(reg.identity)
        callbacks[:unregister].call(reg.identity, mapper) if callbacks[:unregister]
      when TagUpdate
        Nanite::Log.info("RECV #{reg.to_s}")
        nanites.update_tags(reg.identity, reg.new_tags, reg.obsolete_tags)
      else
        Nanite::Log.warn("RECV [register] Invalid packet type: #{reg.class}")
      end
    end

    def nanite_timed_out(token)
      nanite = nanites[token]
      if nanite && timed_out?(nanite)
        Nanite::Log.info("Nanite #{token} timed out")
        nanite = nanites.delete(token)
        callbacks[:timeout].call(token, mapper) if callbacks[:timeout]
        true
      end
    end

    def route(request, targets)
      EM.next_tick { targets.map { |target| publish(request, target) } }
    end

    def publish(request, target)
      # We need to initialize the 'target' field of the request object so that the serializer and
      # the security provider have access to it.
      begin
        old_target = request.target
        request.target = target unless target == 'mapper-offline'
        if @security.authorize_request(request)
          Nanite::Log.info("SEND #{request.to_s([:from, :scope, :tags, :target])}")
          amq.queue(target).publish(serializer.dump(request), :persistent => request.persistent)
        else
          Nanite::Log.error("RECV NOT AUTHORIZED #{request.to_s}")
        end
      ensure
        request.target = old_target
      end
    end

    protected

    # updates nanite information (last ping timestamps, status)
    # when heartbeat message is received
    def handle_ping(ping)
      begin
        if nanite = nanites[ping.identity]
          nanites.update_status(ping.identity, ping.status)
          reaper.update(ping.identity, agent_timeout + 1) { nanite_timed_out(ping.identity) }
        else
          packet = Advertise.new
          Nanite::Log.info("SEND #{packet.to_s} to #{ping.identity}")
          amq.queue(ping.identity).publish(serializer.dump(packet))
        end
      end
    end

    # forward request coming from agent
    def handle_request(request)
      Nanite::Log.info("RECV #{request.to_s([:from, :scope, :target, :tags])}") unless Nanite::Log.level == :debug
      Nanite::Log.debug("RECV #{request.to_s}")
      case request
      when Push
        mapper.send_push(request)
      when Request
        intm_handler = lambda do |result, job|
          result = IntermediateMessage.new(request.token, job.request.from, mapper.identity, nil, result)
          forward_response(result, request.persistent)
        end

        result = Result.new(request.token, request.from, nil, mapper.identity)
        ok = mapper.send_request(request, :intermediate_handler => intm_handler) do |res|
          result.results = res
          forward_response(result, request.persistent)
        end

        if ok == false
          forward_response(result, request.persistent)
        end
      when TagQuery
        results = {}
        results = nanites.nanites_for(request) if request.tags && !request.tags.empty?
        if request.agent_ids && !request.agent_ids.empty?
          request.agent_ids.each do |nanite_id|
            if !results.include?(nanite_id)
              if nanite = nanites[nanite_id]
                results[nanite_id] = nanite
              end
            end
          end
        end
        result = Result.new(request.token, request.from, results, mapper.identity)
        forward_response(result, request.persistent)
      end
    end

    # forward response back to agent that originally made the request
    def forward_response(res, persistent)
      Nanite::Log.info("SEND #{res.to_s([:to])}")
      amq.queue(res.to).publish(serializer.dump(res), :persistent => persistent)
    end

    # returns least loaded nanite that provides given service
    def least_loaded(request, include_timed_out)
      candidates = nanites_providing(request, include_timed_out)
      return [] if candidates.empty?
      res = candidates.to_a.min { |a, b| a[1][:status] <=> b[1][:status] }
      [res[0]]
    end

    # returns all nanites that provide given service
    # potentially including timed out agents
    def all(request, include_timed_out)
      nanites_providing(request, include_timed_out).keys
    end

    # returns a random nanite
    def random(request, include_timed_out)
      candidates = nanites_providing(request, include_timed_out)
      return [] if candidates.empty?
      [candidates.keys[rand(candidates.size)]]
    end

    # selects next nanite that provides given service
    # using round robin rotation
    def rr(request, include_timed_out)
      @last ||= {}
      service = request.type
      @last[service] ||= 0
      candidates = nanites_providing(request, include_timed_out)
      return [] if candidates.empty?
      @last[service] = 0 if @last[service] >= candidates.size
      key = candidates.keys[@last[service]]
      @last[service] += 1
      [key]
    end

    def timed_out?(nanite)
      nanite[:timestamp].to_i < (Time.now.utc - agent_timeout).to_i
    end

    # returns all nanites that provide the given service
    def nanites_providing(request, include_timed_out)
      nanites.nanites_for(request).delete_if do |nanite, info|
        if res = !include_timed_out && timed_out?(info)
          Nanite::Log.debug("Ignoring timed out nanite #{nanite} in target selection - last seen at #{info[:timestamp]}")
        end
        res
      end
    end

    def setup_queues
      setup_heartbeat_queue
      setup_registration_queue
      setup_request_queue
    end

    def setup_heartbeat_queue
      handler = lambda do |ping|
        begin
          ping = serializer.load(ping)
          Nanite::Log.debug("RECV #{ping.to_s}") if ping.respond_to?(:to_s)
          handle_ping(ping)
        rescue Exception => e
          Nanite::Log.error("RECV [ping] #{e.message}")
          callbacks[:exception].call(e, ping, mapper) rescue nil if callbacks[:exception]
        end
      end
      hb_fanout = amq.fanout('heartbeat', :durable => true)
      if shared_state?
        amq.queue("heartbeat").bind(hb_fanout).subscribe &handler
      else
        amq.queue("heartbeat-#{identity}", :exclusive => true).bind(hb_fanout).subscribe &handler
      end
    end

    def setup_registration_queue
      handler = lambda do |msg|
        begin
          register(serializer.load(msg))
        rescue Exception => e
          Nanite::Log.error("RECV [register] #{e.message}")
          callbacks[:exception].call(e, msg, mapper) rescue nil if callbacks[:exception]
        end
      end
      reg_fanout = amq.fanout('registration', :durable => true)
      if shared_state?
        amq.queue("registration").bind(reg_fanout).subscribe &handler
      else
        amq.queue("registration-#{identity}", :exclusive => true).bind(reg_fanout).subscribe &handler
      end
    end

    def setup_request_queue
      handler = lambda do |msg|
        begin
          handle_request(serializer.load(msg))
        rescue Exception => e
          Nanite::Log.error("RECV [request] #{e.message}")
          callbacks[:exception].call(e, msg, mapper) rescue nil if callbacks[:exception]
        end
      end
      req_fanout = amq.fanout('request', :durable => true)
      if shared_state?
        amq.queue("request").bind(req_fanout).subscribe &handler
      else
        amq.queue("request-#{identity}", :exclusive => true).bind(req_fanout).subscribe &handler
      end
    end

    def setup_state
      case @state
      when String
        # backwards compatibility, we assume redis if the configuration option
        # was a string
        require 'nanite/state'
        @nanites = Nanite::State.new(@state, @tag_store)
      else
        require 'nanite/local_state'
        @nanites = Nanite::LocalState.new
      end
    end

    def shared_state?
      !@state.nil?
    end
  end
end
