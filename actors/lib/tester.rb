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

class Tester

  include RightScale::Actor

  expose :test_ack, :test_persistent

  # Receive test_ack command by exiting process if requested
  #
  # === Options
  # :index(Integer):: Message index
  # :exit(Boolean):: Whether to exit process
  #
  # === Return
  # true:: Always return true
  def test_ack(options)
    options = RightScale::SerializationHelper.symbolize_keys(options)
    RightScale::RightLinkLog.info("Received test_ack request, index = #{options[:index]} exit = #{options[:exit]}")
    Process.exit! if options[:exit]
    true
  end

  # Receive test_persistent command and respond with success
  #
  # === Options
  # :index(Integer):: Message index
  #
  # === Return
  # (OperationResult):: Always return success
  def test_persistent(options)
    options = RightScale::SerializationHelper.symbolize_keys(options)
    RightScale::RightLinkLog.info("Received test_persistent request, index = #{options[:index]}")
    RightScale::OperationResult.success(options[:index])
  end

end
