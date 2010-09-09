#
# Copyright (c) 2010 RightScale Inc
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

  # Format the payload of requests and pushes for logging
  class PayloadFormatter

    # Retrieve info log message for given request type and payload
    #
    # === Parameters
    # type(String):: Request type
    # payload(Hash):: Request payload
    #
    # === Return
    # msg(String|NilClass):: Message to be logged or nil (don't log)
    def self.log(type, payload)
      @formatter ||= new
      parts = type.split('/')
      meth = "#{parts[1]}_#{parts[2]}".to_sym
      res = nil
      res = @formatter.send(meth, payload) if @formatter.respond_to?(meth)
      res
    end

    protected
    
    # Retrieve log message for given request type, payload and log level
    #
    # === Parameters
    # type(String):: Request type
    # payload(Hash):: Request payload
    #
    # === Return
    # msg(String|NilClass):: Message to be logged or nil (don't log)
    def self.dispatch(type, payload)
      @formatter ||= new
      parts = type.split('/')
      meth = "#{parts[1]}_#{parts[2]}".to_sym
      res = nil
      res = @formatter.send(meth, payload) if @formatter.respond_to?(meth)
      res
    end

    # state_recorder/record request log message
    # Payload :
    # { :agent_identity => ..., :state => ..., :user_id => ..., :skip_db_update => ..., :kind => ... }
    #
    # === Parameters
    # payload(Hash):: Request payload
    #
    # === Return
    # true:: Always return true
    def state_recorder_record(payload)
      msg = get(payload, :state)
    end

    # booter/declare request log message
    # Payload :
    # { :agent_identity => ..., :r_s_version => ..., :resource_uid => ... }
    #
    # === Parameters
    # payload(Hash):: Request payload
    #
    # === Return
    # true:: Always return true
    def booter_declare(payload)
      msg = get(payload, :resource_uid)
    end 
    
    # forwarder/schedule_right_script request log message
    # Payload :
    # { :audit_id => ..., :token_id => ..., :agent_identity => ..., account_id => ...,
    #   :right_script_id => ..., :right_script => ..., :arguments => ... }
    #
    # === Parameters
    # payload(Hash):: Request payload
    #
    # === Return
    # true:: Always return true
    def forwarder_schedule_right_script(payload)
      msg = get(payload, :right_script) || "RightScript #{get(payload, :right_script_id)}"
    end

    # forwarder/schedule_recipe request log message
    # Payload :
    # { :audit_id => ..., :token_id => ..., :agent_identity => ..., account_id => ...,
    #   :recipe_id => ..., :recipe => ..., :arguments => ..., :json => ... }
    #
    # === Parameters
    # payload(Hash):: Request payload
    #
    # === Return
    # true:: Always return true
    def forwarder_schedule_recipe(payload)
      msg = get(payload, :recipe) || "recipe #{get(payload, :recipe_id)}"
    end


    # Access Hash element where key could be a symbol or a string
    #
    # === Parameters
    # hash(Hash):: Hash containing element to be accessed
    # key(Symbol):: Key of element to be accessed (symbol)
    #
    # === Return
    # elem(Object):: Corresponding element or nil if not found
    def get(hash, key)
      elem = hash[key] || hash[key.to_s]
    end

  end

end

