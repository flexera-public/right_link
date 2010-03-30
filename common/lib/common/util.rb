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

class String
  ##
  # Convert to snake case.
  #
  #   "FooBar".snake_case           #=> "foo_bar"
  #   "HeadlineCNNNews".snake_case  #=> "headline_cnn_news"
  #   "CNN".snake_case              #=> "cnn"
  #
  # @return [String] Receiver converted to snake case.
  #
  # @api public
  def snake_case
    return downcase if match(/\A[A-Z]+\z/)
    gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
    gsub(/([a-z])([A-Z])/, '\1_\2').
    downcase
  end

  ##
  # Convert a constant name to a path, assuming a conventional structure.
  #
  #   "FooBar::Baz".to_const_path # => "foo_bar/baz"
  #
  # @return [String] Path to the file containing the constant named by receiver
  #   (constantized string), assuming a conventional structure.
  #
  # @api public
  def to_const_path
    snake_case.gsub(/::/, "/")
  end

  # Convert constant name to constant
  #
  #    "FooBar::Baz".to_const => FooBar::Baz
  #
  # @return [Constant] Constant corresponding to given name or nil if no
  #   constant with that name exists
  #
  # @api public
  def to_const
    names = split('::')
    names.shift if names.empty? || names.first.empty?

    constant = Object
    names.each do |name|
      # modified to return nil instead of raising an const_missing error
      constant = constant && constant.const_defined?(name) ? constant.const_get(name) : nil
    end
    constant
  end

  # Reverse operation of snake case:
  #
  #    "some_string/some_other_string" => "SomeString::SomeOtherString"
  #
  # @return [String] Camelized string
  #
  # @api public
  if !String.public_method_defined?(:camelize)
    def camelize(first_letter = :upper)
      case first_letter
        when :upper then gsub(/\/(.?)/) { "::" + $1.upcase }.gsub(/(^|_)(.)/) { $2.upcase }
        when :lower then first + camelize(self)[1..-1]
      end
    end
  end

end

class Object
  unless defined? instance_exec # 1.9 and 1.8.7
    module InstanceExecHelper; end
    include InstanceExecHelper

    # Evaluate the block with the given arguments within the context of
    # this object, so self is set to the method receiver.
    #
    # From Mauricio's http://eigenclass.org/hiki/bounded+space+instance_exec
    def instance_exec(*args, &block)
      begin
        old_critical, Thread.critical = Thread.critical, true
        n = 0
        n += 1 while respond_to?(method_name = "__instance_exec#{n}")
        InstanceExecMethods.module_eval { define_method(method_name, &block) }
      ensure
        Thread.critical = old_critical
      end

      begin
        send(method_name, *args)
      ensure
        InstanceExecMethods.module_eval { remove_method(method_name) } rescue nil
      end
    end
  end
end