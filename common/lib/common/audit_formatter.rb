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

  # Standard formatter for audit entries
  # Each method return a hash of two elements:
  #   - :summary contains the updated summary of the audit entry
  #   - :detail contains the details to be appended to the audit entry
  class AuditFormatter

    # Start new audit section
    #
    # === Parameters
    # title(String):: New section title
    #
    # === Return
    # entry(Hash):: Hash containing new audit entry summary and detail
    def self.new_section(title)
      title = '' unless title
      entry = { :summary => title, :detail => "#{ '****' * 20 }\n*RS>#{ title.center(72) }****\n" }
    end

    # Update audit summary
    #
    # === Parameters
    # status(String):: Updated audit status
    #
    # === Return
    # entry(Hash):: Hash containing new audit entry summary and detail
    def self.status(status)
      entry = { :summary => status, :detail => wrap_text(status) }
    end

    # Append output to current audit section
    #
    # === Parameters
    # text(String):: Output to be appended
    #
    # === Return
    # entry(Hash):: Hash containing new audit entry detail
    def self.output(text)
      text += "\n" unless text[-1, 1] == "\n"
      entry = { :detail => text }
    end

    # Append info text to current audit section
    #
    # === Parameters
    # info(String):: Information to be appended
    #
    # === Return
    # entry(Hash):: Hash containing new audit entry detail
    def self.info(text)
      entry = { :detail => wrap_text(text) }
    end

    # Append error text to current audit section
    #
    # === Parameters
    # text(String):: Error message to be appended
    #
    # === Return
    # entry(Hash):: Hash containing new audit entry detail
    def self.error(text)
      entry = { :detail => "*ERROR> #{text}\n" }
    end

    protected

    # Wrap text to given number of columns
    # Tries to be smart and only wrap when there is a space
    #
    # === Parameters
    # txt(String):: Text to be wrapped
    # prefix(String>:: Prefix for each wrapped line, default to '*RS) '
    # col(Integer):: Maximum number of columns for each line, default to 80
    #
    # === Return
    # wrapped_text(String):: Wrapped text
    def self.wrap_text(txt, prefix = '*RS> ', col = 80)
      txt = '' unless txt
      wrapped_text = txt.gsub(/(.{1,#{col - prefix.size}})( +|$\n?)|(.{1,#{col - prefix.size}})/, "#{prefix}\\1\\3\n").rstrip + "\n"     
    end

  end

end
