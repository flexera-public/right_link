#
#
# Copyright (c) 2009-2011 RightScale Inc
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

module Gems

  # Wrapper for the 'gem' command that ensures the systemwide config file is used.
  #
  #
  # @param [String] command the gem command to run
  # @param [optional, Array] *parameters glob of additional command-line parameters to pass to the RubyGems command
  # @example gem('sources', '--list')
  # @example gem('sources', '--add', 'http://awesome-gems.com')
  def self.gem(command, *parameters)
    res = `gem --config-file /etc/gemrc #{command} #{parameters.join(' ')}`
    raise "Error #{RightScale::SubprocessFormatting.reason($?)} executing: `#{command}`: #{res}" unless $? == 0
    res
  end

  module RubyGems #########################################################################

    # The different generate classes will always generate an exception ("string") if there's anything that went wrong. If no exception, things went well.
    def self.generate(description, base_urls, frozen_date="latest")

      #1 - get the current sources
      initial_sources= Gems.gem('sources', '--list').split("\n")
      initial_sources.reject!{|s| s =~ /^\*\*\*/ || s.chomp == "" } # Discard the message (starting with ***) and empty lines returned by gem sources

      #2- Add our sources
      repo_path = "archive/"+ (frozen_date || "latest")
      mirror_list =  base_urls.map do |bu|
        bu +='/' unless bu[-1..-1] == '/' # ensure the base url is terminated with a '/'
        bu+repo_path+ ( repo_path[-1..-1] == '/'? "":"/")
      end
      sources_to_delete = initial_sources-mirror_list # remove good sources from later deletion if we're gonna add them right now.
      mirror_list.map do |m|
        begin
          puts "Adding gem source: #{m}"
          Gems.gem('sources', '--add', m)
        rescue Exception => e
          puts "Error Adding gem source #{m}: #{e}\n...continuing with others..."
        end
      end

      #3-Delete the initial ones (that don't overlap with the new ones)
      sources_to_delete.map do |m|
        begin
          puts "Removing stale gem source: #{m}"
          Gems.gem('sources', '--remove', m)
        rescue Exception => e
          puts "Error Adding gem source #{m}: #{e}\n...continuing with others..."
        end
      end
      mirror_list
    end
  end # Module RubyGems

end

# Examples of usage...
#Gems::RubyGems.generate("RubyGems description", ["http://a.com/rubygems","http://b.com/rubygems"], "20081010")
