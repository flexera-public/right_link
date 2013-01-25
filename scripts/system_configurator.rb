# === Synopsis:
#   RightScale System Configuration Utility (system) - (c) 2011 RightScale Inc
#
#   This utility performs miscellaneous system configuration tasks.
#
# === Examples:
#   system --action=hostname
#   system --action=ssh
#   system --action=proxy
#   system --action=sudoers
#
# === Usage
#    system --action=<action> [options]
#
#    Options:
#      --help:            Display help
#

require 'optparse'
require 'socket'

require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'

# RightLink dependencies
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'agent_config'))

cloud_dir = RightScale::AgentConfig.cloud_state_dir

begin
  require File.join(cloud_dir, 'meta-data-cache')
rescue LoadError => e
  puts "No cloud metadata is available on this machine - some modules may not work correctly!"
end

begin
  require File.join(cloud_dir, 'user-data')
rescue LoadError => e
  puts "No cloud user-data is available on this machine - some modules may not work correctly!"
end

module RightScale
  class SystemConfigurator
    RSA_KEY    = '/etc/ssh/ssh_host_rsa_key'
    DSA_KEY    = '/etc/ssh/ssh_host_dsa_key'
    SUDO_USER  = 'rightscale'
    SUDO_GROUP = 'rightscale_sudo'

    def self.read_options_file
      state = RightScale::Platform.filesystem.right_link_dynamic_state_dir
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
        actions = []
      end

      if actions.empty?
        raise StandardError, "No action specified; try --help"
      end

      actions.each do |action|
        method_name = "configure_#{action}".to_sym
        if action && configurator.respond_to?(method_name)
          puts "Configuring #{action}"
          configurator.__send__(method_name)
        else
          raise StandardError, "Unknown action #{action}"
        end
      end

      return 0
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
      rescue SystemExit => e
        raise e
      rescue Exception => e
        puts e.message + "\nUse --help for additional information"
        exit(1)
      end
      options
    end

    def configure_ssh
      return 0 unless (Platform.linux? || Platform.freebsd?)

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
      return 0 unless (Platform.linux? || Platform.freebsd?)

      hostname     = Socket.gethostname
      current_fqdn = valid_current_fqdn

      if current_fqdn == nil
        # We do not have a valid FQDN; some work is required
        puts "Hostname (#{current_fqdn.inspect}) looks suspect; changing it"
        cloud_fqdn, cloud_ip = retrieve_cloud_hostname_and_local_ip
        set_hostname(cloud_fqdn, cloud_ip)

        # Check if setting the hostname has caused FQDN to work, before
        # adding a fake entry to /etc/hosts as a last resort
        add_host_record(cloud_fqdn, cloud_ip) unless valid_current_fqdn
      else
        # If hostname is already fully-qualified, then do nothing
        puts "Hostname (#{current_fqdn.inspect}) is a well-formed and valid FQDN."
      end
    end

    def configure_proxy
      return 0 unless (Platform.linux? || Platform.freebsd?)

      unset_proxy_variables

      if ENV['RS_HTTP_PROXY']
        puts "Configuring HTTP proxy #{ENV['$RS_HTTP_PROXY']}"

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

    def configure_sudoers
      return 0 unless (Platform.linux? || Platform.freebsd?)
      puts "Configuring /etc/sudoers to ensure rightscale users/groups have sufficient privileges"

      masks = [
        /%?(#{SUDO_GROUP}|#{SUDO_USER}) ALL=(\(ALL\))?NOPASSWD: ALL/,
        /Defaults:(#{SUDO_GROUP}|#{SUDO_USER}) !requiretty/,
        /# RightScale/
      ]

      begin
        lines = File.readlines('/etc/sudoers')
        file = File.open("/etc/sudoers", "w")
        lines.each do |line|
          line.strip!
          next if masks.any? { |m| line =~ m }
          file.puts line
        end

        file.puts("# RightScale: please leave these rules in place, else RightLink may not function")
        file.puts("#{SUDO_USER} ALL=(ALL)NOPASSWD: ALL")
        file.puts("%#{SUDO_GROUP} ALL=NOPASSWD: ALL")
        file.puts("Defaults:#{SUDO_USER} !requiretty")
        file.puts("Defaults:#{SUDO_GROUP} !requiretty")
        file.close
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

    def retrieve_cloud_hostname_and_local_ip
      # Cloud-specific case: query EC2/Eucalyptus metadata to learn local
      # hostname and local public IP address
      if Platform.ec2? || Platform.eucalyptus?
        my_fqdn = ENV['EC2_LOCAL_HOSTNAME']
        my_addr = ENV['EC2_LOCAL_IPV4']

        # Some clouds are buggy and report an IP address as EC2_LOCAL_HOSTNAME.
        # An IP address is not a valid hostname! In this case we must transform
        # it to a valid hostname using the form ip-x-y-z-w where x,y,z,w are
        # the decimal octets of the IP address x.y.z.w
        if my_fqdn =~ /^[0-9.]+$/
          components = my_fqdn.split('.')
          my_fqdn = "ip-#{components.join('-')}.internal"
        end
      end

      # Generic case: use existing hostname and append fake "internal" suffix
      unless my_fqdn
        my_fqdn ||= "#{Socket.gethostname}.internal"
      end

      unless my_addr
        bdns, Socket.do_not_reverse_lookup = Socket.do_not_reverse_lookup, true
        begin
          # Generic case: create a UDP "connection" to our hostname
          # and look at socket data to determine local IP address.
          my_addr = UDPSocket.open do |socket|
            socket.connect(Socket.gethostname, 8000)
            socket.addr.last
          end
        rescue Exception => e
          # Absolute last-ditch effort: use localhost IP.
          # Not ideal, but at least it works...
          my_addr = '127.0.0.1'
        ensure
          Socket.do_not_reverse_lookup = bdns
        end
      end

      [ my_fqdn, my_addr ]
    end

    def valid_current_fqdn
      hostname_f  = Socket.gethostbyname(Socket.gethostname)[0] rescue nil
      if hostname_f && hostname_f.include?('.')
        hostname_f
      else
        nil
      end
    end

    def set_hostname(my_fqdn, my_addr)
      hostname = my_fqdn.split(".").first
      # Set our hostname to the host portion of the FQDN
      runshell("hostname #{hostname}")
      runshell("echo #{hostname} > /etc/hostname")
      puts "Changed hostname to #{hostname}"
    end

    def add_host_record(my_fqdn, my_addr)
      hostname = my_fqdn.split('.').first
      mask = Regexp.new(Regexp.escape(hostname))

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
      no_proxy = []

      if Platform.eucalyptus?
        meta_server = IPSocket.getaddress(euca_metadata) rescue '169.254.169.254'
        no_proxy << meta_server
      else
        #a reasonable default, e.g. for EC2 and for some CloudStack/OpenStack
        #configurations
        no_proxy << '169.254.169.254'
      end

      #parse "skip proxy for these servers" setting out of metadata element
      if ENV['RS_NO_PROXY']
        no_proxy = no_proxy + ENV['RS_NO_PROXY'].split(',')
      end

      no_proxy
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
