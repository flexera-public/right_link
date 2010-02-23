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

  class ActorRegistry

    # (Hash) Actors that are registered; key is actor prefix and value is actor
    attr_reader :actors

    # Initialize registry
    def initialize
      @actors = {}
    end

    # Register as an actor
    #
    # === Parameters
    # actor(Actor):: Actor to be registered
    # prefix(String):: Prefix used in request to identify actor
    #
    # === Return
    # (Actor):: Actor registered
    #
    # === Raises
    # ArgumentError if actor is not an Actor
    def register(actor, prefix)
      raise ArgumentError, "#{actor.inspect} is not a RightScale::Actor subclass instance" unless RightScale::Actor === actor
      log_msg = "[actor] #{actor.class.to_s}"
      log_msg += ", prefix #{prefix}" if prefix && !prefix.empty?
      RightLinkLog.info(log_msg)
      prefix ||= actor.class.default_prefix
      actors[prefix.to_s] = actor
    end

    # Retrieve services provided by all of the registered actors
    #
    # === Return
    # services(Array):: List of unique /prefix/method path strings
    def services
      actors.map {|prefix, actor| actor.class.provides_for(prefix) }.flatten.uniq
    end

    # Retrieve actor by prefix
    #
    # === Parameters
    # prefix(String):: Prefix identifying actor
    #
    # === Return
    # actor(Actor):: Retrieved actor, may be nil
    def actor_for(prefix)
      actor = actors[prefix]
    end

  end # ActorRegistry

end # RightScale 