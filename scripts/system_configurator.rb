# === Synopsis:
#   RightScale System Configuration Utility (system) - (c) 2011 RightScale Inc
#
#   This utility performs miscellaneous system configuration tasks.
#
# === Examples:
#   config hostname
#   config ssh
#   config proxy
#
# === Usage
#    config <action> [options]
#
#    Options:
#      --help:            Display help
#

require 'optparse'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'

begin
  require '/var/spool/cloud/meta-data-cache'
  require '/var/spool/cloud/user-data'
rescue LoadError => e

end

module RightScale
  class SystemConfigurator
    RSA_KEY = '/etc/ssh/ssh_host_rsa_key'
    DSA_KEY = '/etc/ssh/ssh_host_dsa_key'

    def self.read_options_file
      state = RightScale::Platform.filesystem.right_scale_state_dir
      options_file     = File.join(state, 'system.js')
      old_options_file = File.join(state, 'sys_configure.js')

      if File.readable?(options_file)
        return File.read(options_file)
      elsif File.readable?(old_options_file)
        return File.read(old_options_file)
      else
        return nil
      end
    end

    def self.run
      configurator = SystemConfigurator.new
      options = configurator.parse_args

      if (json = read_options_file)
        options.merge(JSON.load(json))
      else
        all_actions  = configurator.methods.select { |m| m =~ /^configure_/ }.map { |m| m[10..-1] }
        options.merge({'actions_enabled' => all_actions})
      end

      if options[:action]
        actions = [ options[:action] ]
      else
        actions = all_actions
      end

      actions.each do |action|
        method_name = "configure_#{action}".to_sym
        if action && configurator.respond_to?(method_name)
          configurator.__send__(method_name)
        else
          raise StandardError, "Unknown action #{action}"
        end
      end

      return 0
    rescue Exception => e
      puts "ERROR: #{e.message}"
      return 1
    end


    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args
      options = { }

      opts = OptionParser.new do |opts|
        opts.on('-a', '--action ACTION') do |action|
          options[:action] = action
        end

        opts.on_tail('--help') do
           puts Usage.scan(__FILE__)
           exit
        end
      end

      begin
        opts.parse!(ARGV)
      rescue Exception => e
        puts e.message + "\nUse --help for additional information"
        exit(1)
      end
      options
    end

    def configure_ssh
      return 0 unless Platform.linux?

      puts "Freshening SSH host keys to ensure they are unique to this instance..."

      if File.readable?(RSA_KEY)
        replace_key(RSA_KEY, 'rsa')
        puts "* replaced RSA key"
        changed = true
      else
        puts "* RSA key does not exist"
      end

      if File.readable?(DSA_KEY)
        replace_key(DSA_KEY, 'dsa')
        puts "* replaced DSA key"
        changed = true
      else
        puts "* DSA key does not exist"
      end

      if changed
        restart_sshd
      end

      return 0
    end

    def configure_hostname
      return 0 unless Platform.linux?

      begin
        hostname    = Socket.gethostname
        hostname_f  = Socket.gethostbyname(hostname)
      rescue Exception => e
        #TO DISCUSS: this block
      end
      # If hostname is already fully-qualified, then do nothing
      if hostname_f[0].include?('.')
        puts "Hostname (#{hostname_f[0]}) is a well-formed and valid FQDN."
      else
        puts "Hostname (#{hostname_f[0]}) looks suspect; changing it"
        my_fqdn, my_addr = retrieve_cloud_hostname_and_local_ip(hostname_f[0])
        add_new_host_record(my_fqdn,my_addr)
      end
    end

    def configure_proxy
      return 0 unless Platform.linux?

      unset_proxy_variables

      if ENV['RS_HTTP_PROXY']
        puts "Configuring HTTP proxy '$RS_HTTP_PROXY'"

        # TODO: super hack for open-uri
        # fix it
        proxy_uri = URI.parse("http://" + ENV['RS_HTTP_PROXY'])

        unless proxy_uri.host && proxy_uri.port
          puts "Proxy specifier is malformed (must contain 'host:port'); skipping proxy."
          return
        end

        # Requests to the metadata server should never be proxied. Detect where our
        # metadata server lives and add this to the no-proxy list automatically.
        no_proxy = get_proxy_exclude_list

        #create global subversion servers config
        create_subversion_servers_config(proxy_uri, no_proxy)

        #create profile.d entry for http_proxy and no_proxy
        create_proxy_profile_script(proxy_uri, no_proxy)
      else
         puts "Proxy settings not found in userdata; continuing without."
      end
    end

    protected

    def runshell(command)
      puts "+ #{command}"
      output = `#{command} < /dev/null 2>&1`
      raise StandardError, "Command failure: #{output}" unless $?.success?
    end

    def replace_key(private_key_file, algorithm)
      public_key_file = "#{private_key_file}.pub"

      puts "Regenerating #{private_key_file}"
      FileUtils.rm(private_key_file) if File.exist?(private_key_file)
      FileUtils.rm(public_key_file) if File.exist?(public_key_file)
      runshell("ssh-keygen -f #{private_key_file} -t #{algorithm} -N ''")
    end

    def restart_sshd
      sshd_name = File.exist?('/etc/init.d/sshd') ? "sshd" : "ssh"
      puts "Restarting SSHD..."
      runshell("/etc/init.d/#{sshd_name} restart")
    end

    def retrieve_cloud_hostname_and_local_ip(hostname)
      rs_cloud = get_cloud_type

      case rs_cloud
        when 'ec2'
          my_fqdn = ENV['EC2_LOCAL_HOSTNAME']
          my_addr = ENV['EC2_PUBLIC_IPV4']
        when 'eucalyptus'
          #my_fqdn = "ip-" + name.gsub(".","-") if my_fqdn.include?('.')
        else
          my_fqdn = "#{hostname}.localdomain"
          my_addr = IPSocket.getaddress(hostname)
      end
      [ my_fqdn, my_addr ]
    end

    def add_new_host_record(my_fqdn, my_addr)
      hostname = my_fqdn.split(".").first
      # Set our hostname to the host portion of the FQDN
      runshell("hostname #{hostname}")
      runshell("echo #{hostname} > /etc/hostname")
      puts "Changed hostname to #{hostname}"

      mask = Regexp.new(hostname)
      begin
        lines = File.readlines('/etc/hosts')
        hosts_file = File.open("/etc/hosts", "w")
        lines.each { |line| hosts_file.puts line.strip unless line =~ mask}
        hosts_file.puts("#{my_addr} #{my_fqdn} #{hostname}")
        hosts_file.close
      end
      puts "Added FQDN hostname entry (#{my_fqdn}) to /etc/hosts"
    end

    def get_proxy_exclude_list
      rs_cloud = get_cloud_type
      no_proxy = []

      no_proxy = []
      case rs_cloud
        when 'eucalyptus'
          meta_server = IPSocket.getaddress(euca_metadata) rescue '169.254.169.254'
          no_proxy << meta_server
        else
          #a reasonable default...
          no_proxy << '169.254.169.254'
      end

      #parse "skip proxy for these servers" setting out of metadata element
      if ENV['RS_NO_PROXY']
        no_proxy = no_proxy + ENV['RS_NO_PROXY'].split(',')
      end

      no_proxy
    end

    # Hack for detecting current Cloud
    def get_cloud_type
      return ENV['RS_CLOUD'] if env['RS_CLOUD']
      cloud_path = '/etc/rightscale.d/cloud'
      rs_cloud = ''
      File.open(cloud_path) { |f| rs_cloud = f.gets } if File.exists?(cloud_path)
      rs_cloud
    end

    def create_subversion_servers_config(proxy_uri, no_proxy_list)
      subversion_servers_path = '/etc/subversion/servers'
      File.open(subversion_servers_path, 'w') do |f|
        f.puts '[global]'

        if proxy_uri && proxy_uri.host && proxy_uri.port
          f.puts "http-proxy-host = #{proxy_uri.host}"
          f.puts "http-proxy-port = #{proxy_uri.port}"
        end

        if no_proxy_list && no_proxy_list.size > 0
          f.puts "http-proxy-exceptions = #{no_proxy_list.join(',')}"
        end
      end
    end

    def create_proxy_profile_script(proxy_uri, no_proxy_list)
      sript_path = '/etc/profile.d/http_proxy.sh'

      File.open(sript_path, 'w') do |f|
        f.puts "# Settings auto-generated by RightScale. Do not change unless you know what"
        f.puts "# you're doing."

        http_proxy = "http_proxy"
        https_proxy = "https_proxy"
        no_proxy = "no_proxy"

        if proxy_uri && proxy_uri.host && proxy_uri.port
          [http_proxy, https_proxy, http_proxy.upcase, https_proxy.upcase].each do |variable|
            f.puts "export #{variable}=\"http://#{proxy_uri.host}:#{proxy_uri.port}\""
          end
        end

        if no_proxy_list && no_proxy_list.size > 0
          [no_proxy, no_proxy.upcase].each do |variable|
            f.puts "export #{variable}=\"#{no_proxy_list.join(',')}\""
          end
        end
      end
    end

    def unset_proxy_variables
      runshell("unset http_proxy ; unset HTTP_PROXY ; unset no_proxy; unset NO_PROXY")
    end
  end
end
