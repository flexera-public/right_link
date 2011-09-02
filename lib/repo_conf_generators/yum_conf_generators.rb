#!/opt/rightscale/sandbox/bin/ruby
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

module Yum
  BaseRepositoryDir="/etc/yum.repos.d" unless defined?(BaseRepositoryDir)

  def self.execute(command)
    res = `#{command}`
    raise "Error #{RightScale::SubprocessFormatting.reason($?)} executing: `#{command}`: #{res}" unless $? == 0
    res
  end

  module CentOS #########################################################################
    RPM_GPG_KEY_CentOS5="file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-5"

    # The different generate classes will always generate an exception ("string") if there's anything that went wrong. If no exception, things went well.
    class Base
      def self.generate(description, base_urls, frozen_date="latest")
        opts = {:repo_filename => "CentOS-Base",
                :repo_name => "base",
                :repo_subpath => "os",
                :description => description,
                :base_urls => base_urls,
                :enabled => true }
        opts[:frozen_date] = frozen_date || "latest" # Optional frozen date
        Yum::CentOS::abstract_generate(opts)
      end
    end

    class Updates
      def self.generate(description, base_urls, frozen_date="latest")
        opts = {:repo_filename => "CentOS-updates",
                :repo_name => "updates",
                :repo_subpath => "updates",
                :description => description,
                :base_urls => base_urls,
                :frozen_date => frozen_date,
                :enabled => true }
        opts[:frozen_date] = frozen_date || "latest" # Optional frozen date
        Yum::CentOS::abstract_generate(opts)
      end
    end

    # The AddOns repository is used in CentOS 5 but not in 6+.
    class AddOns

      def self.generate(description, base_urls, frozen_date="latest")
        # Support CentOS 6+ by NOT generating AddOns repo.
        return unless Yum::CentOS::is_this_centos? && Yum::Epel::get_enterprise_linux_version.to_i < 6

        opts = {:repo_filename => "CentOS-addons",
                  :repo_name => "addons",
                  :repo_subpath => "addons",
                  :description => description,
                  :base_urls => base_urls,
                  :frozen_date => frozen_date,
                  :enabled => true }
        opts[:frozen_date] = frozen_date || "latest" # Optional frozen date
        Yum::CentOS::abstract_generate(opts)
      end
    end

    class Extras
      def self.generate(description, base_urls, frozen_date="latest")
        opts = {:repo_filename => "CentOS-extras",
                :repo_name => "extras",
                :repo_subpath => "extras",
                :description => description,
                :base_urls => base_urls,
                :frozen_date => frozen_date,
                :enabled => true }
        opts[:frozen_date] = frozen_date || "latest" # Optional frozen date
        Yum::CentOS::abstract_generate(opts)
      end
    end

    class CentOSPlus
      def self.generate(description, base_urls, frozen_date="latest")
        opts = {:repo_filename => "CentOS-centosplus",
                :repo_name => "centosplus",
                :repo_subpath => "centosplus",
                :description => description,
                :base_urls => base_urls,
                :frozen_date => frozen_date,
                :enabled => true }
        opts[:frozen_date] = frozen_date || "latest" # Optional frozen date
        Yum::CentOS::abstract_generate(opts)
      end
    end

    ############## INTERNAL FUNCTIONS #######################################################
    def self.abstract_generate(params)
    return unless Yum::CentOS::is_this_centos?
    opts = { :enabled => true, :gpgkey_file => RPM_GPG_KEY_CentOS5, :frozen_date => "latest"}
    opts.merge!(params)
    raise "missing parameters to generate file!" unless opts[:repo_filename] && opts[:repo_name] && opts[:repo_subpath] &&
                                                        opts[:base_urls] && opts[:frozen_date] && opts[:enabled] && opts[:gpgkey_file]
    ver = Yum::execute("lsb_release  -rs").strip
    arch = Yum::execute("uname -i").strip

    if ver =~ /5\.[01]/
      # Old CentOS versions 5.0 and 5.1 were not versioned...so we just point to the base of the repo instead.
      repo_path = "#{ver}/#{opts[:repo_subpath]}/#{arch}"
    else
      repo_path = "#{ver}/#{opts[:repo_subpath]}/#{arch}/archive/"+opts[:frozen_date]
    end

    mirror_list =  opts[:base_urls].map do |bu|
        bu +='/' unless bu[-1..-1] == '/' # ensure the base url is terminated with a '/'
        bu+repo_path
      end
    config_body = <<END
[#{opts[:repo_name]}]
name = #{opts[:description]}
baseurl = #{mirror_list.join("\n ")}
failovermethod=priority
gpgcheck=1
enabled=#{(opts[:enabled] ? 1:0)}
gpgkey=#{opts[:gpgkey_file]}
END

    target_filename = "#{Yum::BaseRepositoryDir}/#{opts[:repo_filename]}.repo"
    File.rename(target_filename,"#{Yum::BaseRepositoryDir}/.#{opts[:repo_filename]}.repo.#{`date +%Y%m%d%M%S`.strip}") if File.exists?("#{Yum::BaseRepositoryDir}/#{opts[:repo_filename]}.repo")
    File.open(target_filename,'w') { |f| f.write(config_body) }
    puts "Yum config file for CentOS successfully generated in #{target_filename}"
    mirror_list
    end

    def self.is_this_centos?
      return ::RightScale::Platform.linux? && ::RightScale::Platform.centos?
    end

  end # Module CentOS

  module Epel #####################################################################
    RPM_GPG_KEY_EPEL="file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL"
    def self.generate(description, base_urls, frozen_date = "latest")
      opts = {:repo_filename => "Epel",
        :repo_name => "epel",
        :description => description,
        :base_urls => base_urls,
        :frozen_date => frozen_date,
        :enabled => true }
      opts[:frozen_date] = frozen_date || "latest" # Optional frozen date
      Yum::Epel::abstract_generate(opts)
    end
    ############## INTERNAL FUNCTIONS #######################################################
    def self.abstract_generate(params)
    return unless Yum::CentOS::is_this_centos?

    epel_version = get_enterprise_linux_version
    puts "found EPEL version: #{epel_version}"
    opts = { :enabled => true, :gpgkey_file => RPM_GPG_KEY_EPEL, :frozen_date => "latest"}
    opts.merge!(params)
    raise "missing parameters to generate file!" unless opts[:repo_filename] && opts[:repo_name] &&
                                                        opts[:base_urls] && opts[:frozen_date] && opts[:enabled] && opts[:gpgkey_file]

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
gpgcheck=1
enabled=#{(opts[:enabled] ? 1:0)}
gpgkey=#{opts[:gpgkey_file]}
END

    target_filename = "#{Yum::BaseRepositoryDir}/#{opts[:repo_filename]}.repo"
    File.rename(target_filename,"#{Yum::BaseRepositoryDir}/.#{opts[:repo_filename]}.repo.#{`date +%Y%m%d%M%S`.strip}") if File.exists?("#{Yum::BaseRepositoryDir}/#{opts[:repo_filename]}.repo")
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

# Examples of usage...
#Yum::CentOS::Base.generate("Centos base description", ["http://a.com/centos","http://b.com/centos"], "20081010")
#Yum::CentOS::AddOns.generate("Centos addons description", ["http://a.com/centos","http://b.com/centos"], "latest")
#Yum::CentOS::Updates.generate("Centos updates description", ["http://a.com/centos","http://b.com/centos"], ) # Nil also means not frozen (i.e., equivalent to latest)
#Yum::CentOS::Extras.generate("Centos extras description", ["http://a.com/centos","http://b.com/centos"], "latest")
#Yum::CentOS::CentOSPlus.generate("Centos centosplus description", ["http://a.com/centos","http://b.com/centos"], "latest")
#Yum::Epel.generate("Epel description", ["http://a.com/epel","http://b.com/epel"], "20081010")
