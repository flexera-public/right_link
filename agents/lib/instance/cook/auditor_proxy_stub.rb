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

require 'singleton'

module RightScale

  # Provides access to RightLink agent audit methods
  class AuditorProxyStub

    include Singleton

    # Initialize command protocol, call prior to calling any instance method
    #
    # === Parameters
    # options[:listen_port]:: Command server listen port
    # options[:cookie]:: Command protocol cookie
    #
    # === Return
    # true:: Always return true
    def self.init(client)
      @@client = client
      true
    end

    # Update audit summary
    #
    # === Parameters
    # status(String):: New audit entry status
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    # options[:audit_id](Integer):: Audit id
    #
    # === Return
    # true:: Always return true
    def update_status(status, options={})
      send_command(:audit_update_status, status, options)
    end

    # Start new audit section
    #
    # === Parameters
    # title(String):: Title of new audit section, will replace audit status as well
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    # options[:audit_id](Integer):: Audit id
    #
    # === Return
    # true:: Always return true
    def create_new_section(title, options={})
      send_command(:audit_create_new_section, title, options)
    end

    # Append output to current audit section
    #
    # === Parameters
    # text(String):: Output to append to audit entry
    # options[:audit_id](Integer):: Audit id
    #
    # === Return
    # true:: Always return true
    def append_output(text, options)
      send_command(:audit_append_output, text, options)
    end

    # Append info text to current audit section. A special marker will be prepended to each line of audit to
    # indicate that text is not some output. Text will be line-wrapped.
    #
    # === Parameters
    # text(String):: Informational text to append to audit entry
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    # options[:audit_id](Integer):: Audit id
    #
    # === Return
    # true:: Always return true
    def append_info(text, options={})
      send_command(:audit_append_info, text, options)
    end

    # Append error message to current audit section. A special marker will be prepended to each line of audit to
    # indicate that error message is not some output. Message will be line-wrapped.
    #
    # === Parameters
    # text(String):: Error text to append to audit entry
    # options[:audit_id](Integer):: Audit id
    #
    # === Return
    # true:: Always return true
    def append_error(text, options={})
      send_command(:audit_append_error, text, options)
    end

    protected
    
    # Helper method used to send command client request to RightLink agent
    #
    # === Parameters
    # cmd(String):: Command name
    # content(String):: Audit content
    # options(Hash):: Audit options
    #
    # === Return
    # true:: Always return true
    def send_command(cmd, content, options={})
      options ||= {}
      begin
        cmd = { :name => cmd, :content => content, :options => options }
        @@client.send_command(cmd) do |res|
          unless res == "OK"
            $stderr.puts 'Failed to audit'
            $stderr.puts "Failed to audit (#{cmd[:name]}) - #{res}"
          end
        end
      rescue Exception => e
        $stderr.puts 'Failed to audit'
        $stderr.puts "Failed to audit (#{cmd[:name]}) - #{e.message} from\n#{e.backtrace.join("\n")}"
      end
    end

  end

end
