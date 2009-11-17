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
require 'thread'

module RightScale
  class LoginManager
    include Singleton

    ROOT_TRUSTED_KEYS_FILE = '/root/.ssh/authorized_keys'
    ACTIVE_TAG             = 'rs_managed_login:state=active'      

    def update_policy(new_policy)
      return false unless RightLinkConfig.platform.linux?

      @mutex ||= Mutex.new
      
      new_lines = new_policy.users.map { |u| u.public_key }

      #Perform updates to the file and the stored policy inside a critical section, just in case
      #two threads try to call this method concurrently (not likely, but disastrous if it were to happen...)
      @mutex.synchronize do
        #If the new policy isn't exclusive, we need to preserve any existing lines in authorized_keys
        #which we did not put there ourselves. Perform a three-way merge on the existing file contents.
        if @policy && !new_policy.exclusive
          system_lines = read_keys()
          old_lines    = @policy.users.map { |u| u.public_key }
          new_lines    = merge_keys(system_lines, old_lines, new_lines)
        end

        write_keys(new_lines)
        @policy = new_policy
      end
      
      AgentTagsManager.instance.add_tags(ACTIVE_TAG)
      return true
    end

    protected

    def read_keys()
      return [] unless File.exist?(ROOT_TRUSTED_KEYS_FILE)
      File.readlines(ROOT_TRUSTED_KEYS_FILE).map! { |l| l.chomp.strip }
    end

    def write_keys(keys)
      dir = File.dirname(ROOT_TRUSTED_KEYS_FILE)
      FileUtils.mkdir_p(dir)
      FileUtils.chmod(0700, dir)

      File.open(ROOT_TRUSTED_KEYS_FILE, 'w') do |f|
        keys.each { |k| f.puts k }
      end

      FileUtils.chmod(0600, ROOT_TRUSTED_KEYS_FILE)
    end

    def merge_keys(system_lines, old_lines, new_lines)
      file_triples = system_lines.map { |l| l.split(/\s+/) }
      system_idx = Set.new
      file_triples.each { |t| system_idx << t[0..1] }

      old_triples = old_lines.map { |l| l.split(/\s+/) }
      old_idx = Set.new
      old_triples.each { |t| new << t[0..1] }

      new_triples = new_lines.map { |l| l.split(/\s+/) }
      new_idx = Set.new
      new_triples.each { |t| new_idx << t[0..1] }

      preserve_idx = system_idx - old_idx - new_idx

      effective_triples = file_triples.select { |t| preserve_idx.include? } + new_triples
      return effective_triples.map { |t| t.join(' ') }
    end
  end 
end