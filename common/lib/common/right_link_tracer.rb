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

# This allows us to define class methods
class Object
  def metaclass
    class << self
      self
    end
  end
end

module RightScale

  class RightLinkTracer

    NON_TRACEABLE_CLASSES = [ 'Kernel', 'Module', 'Object' , 'SyslogLogger', 'RightSupport::SystemLogger' ] +
                            [ 'RightScale::RightLinkTracer', 'RightScale::Multiplexer' ] +
                            [ 'RightScale::RightLinkLog', 'RightScale::RightLinkLog::Formatter' ]

    NON_TRACEABLE_METHODS = [ :metaclass, :method_missing, :method_added, :blank_slate_method_added, :[], :[]= ]

    NON_TRACEABLE_CLASS_METHODS = [ :initialize, :initialize_copy, :inherited, :new, :allocate, :superclass ]

    # Add logs when entering and exiting instance and class methods
    # defined on given class
    #
    # === Parameters
    # klass(Class):: Class whose methods should be traced
    #
    # === Return
    # true:: Always return true
    def self.add_tracing_to_class(klass)
      return true if NON_TRACEABLE_CLASSES.include?(klass.to_s)
      (klass.public_instance_methods(all=false) + klass.private_instance_methods(all=false) +
              klass.protected_instance_methods(all=false)).each do |m|
        if traceable(m)
          old_m = klass.instance_method(m)
          klass.module_eval <<-EOM
            alias :o_l_d_#{m} :#{m}
            def #{m}(*args, &blk)
              RightLinkLog.debug("<<< #{klass}##{m}(" + args.map(&:inspect).join(',') + ")")
              res = o_l_d_#{m}(*args, &blk)
              RightLinkLog.debug(">>> #{klass}##{m}")
              res
            end
          EOM
        end
      end
      (klass.public_methods(all=false) + klass.private_methods(all=false) +
              klass.protected_methods(all=false)).each do |m|
        if traceable(m, static=true)
          old_m = klass.method(m)
          klass.module_eval <<-EOM
            class << self
              alias :o_l_d_#{m} :#{m}
              def #{m}(*args, &blk)
                RightLinkLog.debug("<<< #{klass}.#{m}(" + args.map(&:inspect).join(',') + ")")
                res = o_l_d_#{m}(*args, &blk)
                RightLinkLog.debug(">>> #{klass}.#{m}")
                res
              end
            end
          EOM
        end
      end
      true
    end

    # Can method be traced?
    #
    # === Parameters
    # m(String):: Method name
    # static(Boolean):: Whether method is a class method
    #
    # === Return
    # traceable(Boolean):: true if method can be traced, false otherwise
    def self.traceable(m, static=false)
      traceable = !NON_TRACEABLE_METHODS.include?(m.to_sym) && m =~ /[a-zA-Z0-9]$/
      traceable &&= !NON_TRACEABLE_CLASS_METHODS.include?(m.to_sym) if static
      traceable
    end

    # Add tracing to all classes in given namespaces
    #
    # === Parameters
    # namespaces(Array|String):: Namespace(s) of classes whose methods should be traced
    #
    # === Return
    # true:: Always return true
    def self.add_tracing_to_namespaces(namespaces)
      namespaces = [ namespaces ] unless namespaces.respond_to?(:inject)
      regexps = namespaces.inject([]) { |reg, n| reg << "^#{n}::" }
      unless regexps.empty?
        ObjectSpace.each_object(Class) do |c|
          if c.to_s =~ /#{regexps.join('|')}/
            add_tracing_to_class(c)
          end
        end
      end 
      true
    end

  end
end
