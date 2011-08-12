#!/opt/rightscale/sandbox/bin/ruby
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

module Apt

  module Ubuntu
    SUPPORTED_REPOS = ['hardy', 'intrepid', 'jaunty', 'karmic', 'lucid', 'maverick' ]

    # The different generate classes will always generate an exception ("string") if there's anything that went wrong. If no exception, things went well.
    [ 'Hardy', 'Intrepid', 'Jaunty', 'Karmic' , 'Lucid', 'Maverick' ].each do |c|
      module_eval <<-EOS
        class #{c}
          def self.generate(description, base_urls, frozen_date="latest")
            opts = { :repo_filename => "rightscale",
                     :repo_name     => "default",
                     :description   => description,
                     :base_urls     => base_urls,
                     :frozen_date   => frozen_date,
                     :enabled       => true }
            opts[:frozen_date] = frozen_date || "latest" # Optional frozen date
            Apt::Ubuntu::abstract_generate(opts)
          end
        end
      EOS
    end

    def self.path_to_sources_list
      "/etc/apt/sources.list.d"
    end

    ############## INTERNAL FUNCTIONS #######################################################
    def self.abstract_generate(params)
      return unless ::RightScale::Platform.linux? && ::RightScale::Platform.linux.ubuntu?

      opts = { :enabled => true, :frozen_date => "latest"}
      opts.merge!(params)
      raise ArgumentError.new("missing parameters to generate file!") unless opts[:repo_filename] &&
                                                                      opts[:repo_name] &&
                                                                      opts[:base_urls] &&
                                                                      opts[:frozen_date] &&
                                                                      opts[:enabled]

      return unless opts[:enabled]

      codename = ::RightScale::Platform.linux.codename.downcase
      raise RightScale::PlatformError.new("Unsupported ubuntu release #{codename}") unless SUPPORTED_REPOS.include?(codename)
      FileUtils.mkdir_p(Apt::Ubuntu::path_to_sources_list)

      if opts[:frozen_date] != 'latest'
        x = Date.parse(opts[:frozen_date]).to_s
        x.gsub!(/-/,"/")
        opts[:frozen_date] = x
      end

      mirror_list =  opts[:base_urls].map do |bu|
        bu +='/' unless bu[-1..-1] == '/' # ensure the base url is terminated with a '/'
        bu + opts[:frozen_date]
      end
      config_body = ""
      mirror_list.each do |mirror_url|
        config_body += <<END
deb #{mirror_url} #{codename} main restricted multiverse universe
deb #{mirror_url} #{codename}-updates main restricted multiverse universe
deb #{mirror_url} #{codename}-security main restricted multiverse universe

END
      end

      target_filename = "#{Apt::Ubuntu::path_to_sources_list}/#{opts[:repo_filename]}.sources.list"
      FileUtils.rm_f(target_filename) if File.exists?(target_filename)
      File.open(target_filename,'w') { |f| f.write(config_body) }
      FileUtils.mv("/etc/apt/sources.list", "/etc/apt/sources.list.ORIG") if File.exists?("/etc/apt/sources.list")

      mirror_list
    end
  end
end

# Examples of usage...
#Apt::Ubuntu::Hardy.generate("Hardy", ["http://a.com/ubuntu_daily"], "20081010")
