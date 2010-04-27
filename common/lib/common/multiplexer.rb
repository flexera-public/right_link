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

  # Apply each method call to all registered targets
  class Multiplexer
   
    # Access to underlying multiplexed objects
    attr_reader :targets

    # Undefine warn to prevent Kernel#warn from being called
    undef warn

    # Initialize multiplexer targets
    #
    # === Parameters
    # targets(Object):: Targets that should receive the method calls
    def initialize(*targets)
      @targets = targets || []
    end

    # Add object to list of multiplexed targets
    #
    # === Parameters
    # target(Object):: Add target to list of multiplexed targets
    #
    # === Return
    # self(RightScale::Multiplexer):: self so operation can be chained
    def add(target)
      @targets << target unless @targets.include?(target)
      self
    end

    # Remove object from list of multiplexed targets
    #
    # === Parameters
    # target(Object):: Remove target from list of multiplexed targets
    #
    # === Return
    # self(RightScale::Multiplexer):: self so operation can be chained
    def remove(target)
      @targets.delete_if { |t| t == target }
      self
    end

    # Access target at given index
    #
    # === Parameters
    # index(Integer):: Target index
    #
    # === Return
    # target(Object):: Target at index 'index' or nil if none
    def [](index)
      target = @targets[index]
    end

    # Forward any method invokation to targets
    #
    # === Parameters
    # m(Symbol):: Method that should be multiplexed
    # args(Array):: Arguments
    #
    # === Return
    # res(Object):: Result of first target in list
    def method_missing(m, *args)
      res = @targets.inject([]) { |res, t| res << t.__send__(m, *args) }
      res[0]
    end

  end
end
