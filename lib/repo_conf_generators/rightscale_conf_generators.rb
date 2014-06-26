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

require 'fileutils'
require 'date'

module Yum
  BaseRepositoryDir="/etc/yum.repos.d" unless defined?(BaseRepositoryDir)

  def self.execute(command)
    res = `#{command}`
    raise "Error #{RightScale::SubprocessFormatting.reason($?)} executing: `#{command}`: #{res}" unless $? == 0
    res
  end

  module RightScale
    module Epel #####################################################################
      def self.generate(description, base_urls, frozen_date = "latest")
        opts = {:repo_filename => "RightScale-epel",
          :repo_name => "rightscale-epel",
          :description => description,
          :base_urls => base_urls,
          :frozen_date => frozen_date,
          :enabled => true }
        opts[:frozen_date] = frozen_date || "latest" # Optional frozen date
        Yum::RightScale::Epel::abstract_generate(opts)
      end
      module Testing #########################Epel-testing ###########################
        def self.generate(description, base_urls, frozen_date = "latest")
          opts = {:repo_filename => "RightScale-epel-testing",
            :repo_name => "rightscale-epel-testing",
            :description => description,
            :base_urls => base_urls,
            :frozen_date => frozen_date,
            :enabled => true }
          opts[:frozen_date] = frozen_date || "latest" # Optional frozen date
          Yum::RightScale::Epel::abstract_generate(opts)
        end
      end

      ############## INTERNAL FUNCTIONS #######################################################
      def self.abstract_generate(params)
        return unless Yum::RightScale::Epel::yum_installed?

        epel_version = get_enterprise_linux_version
        puts "found EPEL version: #{epel_version}"
        opts = { :enabled => true, :frozen_date => "latest"}
        opts.merge!(params)
        raise "missing parameters to generate file!" unless opts[:repo_filename] && opts[:repo_name] &&
          opts[:base_urls] && opts[:frozen_date] && opts[:enabled]

        arch = Yum::execute("uname -i").strip

        repo_path = "#{epel_version}/#{arch}/archive/"+opts[:frozen_date]
        mirror_list =  opts[:base_urls].map do |bu|
          bu +='/' unless bu[-1..-1] == '/' # ensure the base url is terminated with a '/'
          bu+repo_path
        end

        gpgcheck = "1"
        unless Yum::RightScale::Epel::rightscale_gpgkey_imported?
          gpgfile = "/etc/pki/rpm-gpg/RPM-GPG-KEY-RightScale"
          if File.exists?(gpgfile)
            # This file should be installed by the rightimage cookbook
            # starting with 12H1 (May 2012)
            gpgkey = "file://#{gpgfile}"
            gpgcheck = "1"
          else
            gpgfile = File.expand_path("../rightscale_key.pub", __FILE__)
            Yum::execute("rpm --import #{gpgfile}")
            gpgcheck = "1"
            gpgkey = ""
          end
        end
        config_body = <<END
[#{opts[:repo_name]}]
name = #{opts[:description]}
baseurl = #{mirror_list.join("\n ")}
failovermethod=priority
gpgcheck=#{gpgcheck}
enabled=#{(opts[:enabled] ? 1:0)}
gpgkey=#{gpgkey}
# set metadata to expire faster then main
metadata_expire=30
END

        target_filename = "#{Yum::BaseRepositoryDir}/#{opts[:repo_filename]}.repo"
        File.rename(target_filename,"#{Yum::BaseRepositoryDir}/.#{opts[:repo_filename]}.repo.#{`date +%Y%m%d%M%S`.strip}") if File.exists?("#{Yum::BaseRepositoryDir}/#{opts[:repo_filename]}.repo")
        File.open(target_filename,'w') { |f| f.write(config_body) }
        puts "Yum config file for Epel successfully generated in #{target_filename}"
        mirror_list
      end

      def self.yum_installed?
        if ::RightScale::Platform.linux? && (::RightScale::Platform.centos? || ::RightScale::Platform.rhel?)
          true
        else
          false
        end
      end

      def self.rightscale_gpgkey_imported?
        begin
          Yum::execute("rpm -qa gpg-pubkey --qf '%{summary}\n' | grep RightScale")
          true
        rescue
          false
        end
      end

      # Return the enterprise linux version of the running machine...or an exception if it's a non-enterprise version of linux.
      # At this point we will only test for CentOS ... but in the future we can test RHEL, and any other compatible ones
      # Note the version is a single (major) number.
      def self.get_enterprise_linux_version
        version=nil
        if Yum::RightScale::Epel::yum_installed?
          version = Yum::execute("lsb_release  -rs").strip.split(".").first
        else
          raise "This doesn't appear to be an Enterprise Linux edition"
        end
        version
      end

    end

  end
end

# Examples of usage...
#Yum::RightScale::Epel.generate("Epel description", ["http://a.com/epel","http://b.com/epel"], "20081010")

module Apt

  def self.execute(command)
    res = `#{command}`
    raise "Error #{RightScale::SubprocessFormatting.reason($?)} executing: `#{command}`: #{res}" unless $? == 0
    res
  end

  module RightScale
    SUPPORTED_REPOS = ['lucid', 'precise', 'trusty']

    # The different generate classes will always generate an exception ("string") if there's anything that went wrong. If no exception, things went well.
    SUPPORTED_REPOS.each do |c|
      module_eval <<-EOS
        class #{c.capitalize}
          def self.generate(description, base_urls, frozen_date="latest")
            opts = { :repo_filename => "rightscale_extra",
                     :repo_name     => "default",
                     :description   => description,
                     :codename      => '#{c}',
                     :base_urls     => base_urls,
                     :frozen_date   => frozen_date,
                     :enabled       => true }
            opts[:frozen_date] = frozen_date || "latest" # Optional frozen date
            Apt::RightScale::abstract_generate(opts)
          end
        end
      EOS
    end

    def self.path_to_sources_list
      "/etc/apt/sources.list.d"
    end

    def self.rightscale_gpgkey_imported?
      begin
        Apt::execute("apt-key list | grep RightScale")
        true
      rescue
        false
      end
    end

    ############## INTERNAL FUNCTIONS #######################################################
    def self.abstract_generate(params)
      return unless ::RightScale::Platform.linux? && ::RightScale::Platform.ubuntu?

      opts = { :enabled => true, :frozen_date => "latest"}
      opts.merge!(params)
      raise ArgumentError.new("missing parameters to generate file!") unless opts[:repo_filename] &&
                                                                      opts[:repo_name] &&
                                                                      opts[:base_urls] &&
                                                                      opts[:frozen_date] &&
                                                                      opts[:enabled]

      return unless opts[:enabled]

      target = opts[:codename].downcase
      codename = ::RightScale::Platform.codename.downcase

      raise ::RightScale::Exceptions::PlatformError, "Unsupported Ubuntu release #{codename}" unless SUPPORTED_REPOS.include?(codename)
      raise ::RightScale::Exceptions::PlatformError, "Wrong release; repo is for #{target}, we are #{codename}" unless target == codename

      FileUtils.mkdir_p(Apt::RightScale::path_to_sources_list)


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
deb #{mirror_url} #{codename} main

END
      end

      target_filename = "#{Apt::RightScale::path_to_sources_list}/#{opts[:repo_filename]}.sources.list"
      FileUtils.rm_f(target_filename) if File.exists?(target_filename)
      File.open(target_filename,'w') { |f| f.write(config_body) }
      FileUtils.mv("/etc/apt/sources.list", "/etc/apt/sources.list.ORIG") if File.size?("/etc/apt/sources.list")
      FileUtils.touch("/etc/apt/sources.list")

      unless Apt::RightScale::rightscale_gpgkey_imported?
        gpgfile = File.expand_path("../rightscale_key.pub", __FILE__)
        Apt::execute("apt-key add #{gpgfile}")
      end

      mirror_list
    end
  end
end


# Examples of usage...
#Apt::RightScale::Lucid.generate("Lucid", [""http://a.com/rightscale_software_ubuntu""], "20081010")
