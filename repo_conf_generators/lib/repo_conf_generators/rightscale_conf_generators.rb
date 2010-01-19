#!/opt/rightscale/sandbox/bin/ruby
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

module Yum
  BaseRepositoryDir="/etc/yum.repos.d" unless defined?(BaseRepositoryDir)

  def self.execute(command)
    res = `#{command}`
    raise "Error #{$?.exitstatus} executing: `#{command}`: #{res}" unless $? == 0
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
        config_body = <<END
[#{opts[:repo_name]}]
name = #{opts[:description]}
baseurl = #{mirror_list.join("\n ")}
failovermethod=priority
gpgcheck=0
enabled=#{(opts[:enabled] ? 1:0)}
gpgkey=#{opts[:gpgkey_file]}
# set metadata to expire faster then main
metadata_expire=30
END

        target_filename = "#{Yum::BaseRepositoryDir}/#{opts[:repo_filename]}.repo"
        File.rename(target_filename,"#{Yum::BaseRepositoryDir}/.#{opts[:repo_filename]}.repo.#{`date +%Y%m%d%M%S`.strip}") if File.exist?("#{Yum::BaseRepositoryDir}/#{opts[:repo_filename]}.repo")
        File.open(target_filename,'w') { |f| f.write(config_body) }
        puts "Yum config file for Epel successfully generated in #{target_filename}"
        mirror_list
      end

      # Return the enterprise linux version of the running machine...or an exception if it's a non-enterprise version of linux.
      # At this point we will only test for CentOS ... but in the future we can test RHEL, and any other compatible ones
      # Note the version is a single (major) number.
      def self.get_enterprise_linux_version
        version=nil
        if Yum::CentOS::is_this_centos?
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
#Yum::CentOS::Base.generate("Centos base description", ["http://a.com/centos","http://b.com/centos"], "20081010")
#Yum::CentOS::AddOns.generate("Centos addons description", ["http://a.com/centos","http://b.com/centos"], "latest")
#Yum::CentOS::Updates.generate("Centos updates description", ["http://a.com/centos","http://b.com/centos"], ) # Nil also means not frozen (i.e., equivalent to latest)
#Yum::CentOS::Extras.generate("Centos extras description", ["http://a.com/centos","http://b.com/centos"], "latest")
#Yum::CentOS::CentOSPlus.generate("Centos centosplus description", ["http://a.com/centos","http://b.com/centos"], "latest")
#Yum::Epel.generate("Epel description", ["http://a.com/epel","http://b.com/epel"], "20081010")
