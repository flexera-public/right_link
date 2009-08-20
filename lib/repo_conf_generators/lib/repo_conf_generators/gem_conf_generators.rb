#!/usr/bin/env ruby
# Copyright (c) 2008 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.

module Gems

  def self.execute(command)
    res = `#{command}`
    raise "Error #{$?.exitstatus} executing: `#{command}`: #{res}" unless $? == 0
    res
  end

  module RubyGems #########################################################################

    # The different generate classes will always generate an exception ("string") if there's anything that went wrong. If no exception, things went well.
    def self.generate(description, base_urls, frozen_date="latest")

      #1 - get the current sources
      initial_sources= Gems::execute("gem sources").split("\n")
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
          Gems::execute("gem sources -a #{m}")
        rescue Exception => e
          puts "Error Adding gem source #{m}: #{e}\n...continuing with others..."
        end
      end

      #3-Delete the initial ones (that don't overlap with the new ones)
      sources_to_delete.map do |m|
        begin
          puts "Removing stale gem source: #{m}"
          Gems::execute("gem sources -r #{m}")
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
