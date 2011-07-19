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

# This file may get required twice on Windows: Once using long path and once 
# using short path. Since this is where we define the File.normalize_path
# method to alleviate this issue, we have a chicken & egg problem. So detect if
# we already required this file and skip the rest if that was the case
unless defined?(RightScale::Platform)

# note that the plaform-specific submodules will be loaded on demand to resolve
# some install-time gem dependency issues.

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'common', 'lib', 'common', 'util'))

module RightScale

  # A utility class that provides information about the platform on which RightLink is running.
  # Available information includes:
  #  * which flavor cloud (EC2, Rackspace, Eucalyptus, ..)
  #  * which flavor operating system (Linux, Windows or Mac)
  #  * which OS release (a numeric value that is specific to the OS)
  #  * directories in which various bits of RightScale state may be found
  #  * platform-specific information such as Linux distro or release codename
  #
  # NB: In general, you should not use the filesystem methods directly to
  # query RightLink agent configuration; instead, use the RightScale::RightLinkConfig
  # class.
  #
  # You may query the Platform by instantiating an instance of if (Platform.new) and then calling
  # its various methods, many of which return an object that can be further queried. This provides
  # a DSL-like way to query the platform about its various features.
  #
  # As a shortcut, if you call a missing method of the Platform CLASS that is an instance method,
  # the class will instantiate a new instance for you and call the method you specified. Thus, the
  # following are equivalent:
  # * Platform.new.filesystem
  # * Platform.filesystem
  #
  # A summary of the information you can query by calling Platform's instance methods:
  # * .linux?
  # * .mac?
  # * .windows?
  # * .ec2?
  # * .rackspace?
  # * .eucalyptus?
  # * .filesystem
  #   * right_scale_state_dir
  #   * spool_dir
  #   * cache_dir
  # * .linux (only available under Linux)
  #   * ubuntu?
  #   * centos?
  #   * distro
  #   * release
  #   * codename
  class Platform

    @@instance = nil

    # Initialize platform values
    def initialize
      @windows = !!(RUBY_PLATFORM =~ /mswin/)
      @mac     = !!(RUBY_PLATFORM =~ /darwin/)
      @linux   = !!(RUBY_PLATFORM =~ /linux/)

      @filesystem     = nil
      @volume_manager = nil
      @shell          = nil
      @ssh            = nil
      @controller     = nil

      @ec2        = nil
      @rackspace  = nil
      @eucalyptus = nil

      # note that we must defer any use of filesystem until requested because
      # Windows setup scripts attempt to use Platform before installing some
      # of the required gems. don't attempt to call code that requires gems in
      # initialize().
    end

    # Load platform specific implementation
    #
    # === Return
    # true:: Always return true
    def load_platform_specific
      if linux?
        require_linux
      elsif mac?
        require_mac
      elsif windows?
        require_windows
      else
        raise PlatformError.new('Unknown platform')
      end
    end
    
    # An alias for RUBY_PLATFORM
    #
    # === Return
    # name(String):: RUBY_PLATFORM
    def name
      RUBY_PLATFORM
    end

    # Is current platform windows?
    #
    # === Return
    # true:: If ruby interpreter is running on Windows
    # false:: Otherwise
    def windows?
      @windows
    end

    # Is current platform Mac OS X (aka Darwin)?
    #
    # === Return
    # true:: If ruby interpreter is running on Mac
    # false:: Otherwise
    def mac?
      @mac
    end

    # Is current platform linux?
    #
    # === Return
    # true:: If ruby interpreter is running on Linux
    # false:: Otherwise
    def linux?
      @linux
    end

    # Are we in an EC2 cloud?
    #
    # === Return
    # true:: If machine is located in an EC2 cloud
    # false:: Otherwise
    def ec2?
      resolve_cloud_type if @ec2.nil?
      @ec2
    end

    # Are we in a Rackspace cloud?
    #
    # === Return
    # true:: If machine is located in an EC2 cloud
    # false:: Otherwise
    def rackspace?
      resolve_cloud_type if @rackspace.nil?
      @rackspace
    end

    # Are we in a Eucalyptus cloud?
    #
    # === Return
    # true:: If machine is located in an EC2 cloud
    # false:: Otherwise
    def eucalyptus?
      resolve_cloud_type if @eucalyptus.nil?
      @eucalyptus
    end

    # Controller object
    #
    # === Return
    # c(Controller):: Platform-specific controller object
    def controller
      platform_service(:controller)
    end

    # Filesystem config object
    #
    # === Return
    # fs(Filesystem):: Platform-specific filesystem config object
    def filesystem
      platform_service(:filesystem)
    end

    # VolumeManager config object
    #
    # === Return
    # vm(VolumeManager):: Platform-specific volume manager config object
    def volume_manager
      platform_service(:volume_manager)
    end

    # Shell information object
    #
    # === Return
    # platform specific shell information object
    def shell
      platform_service(:shell)
    end

    # SSH information object
    #
    # === Return
    # platform specific ssh object
    def ssh
      platform_service(:ssh)
    end

    # Platform random number generator (RNG) facilities.
    #
    # === Return
    # platform specific RNG object
    def rng
      platform_service(:rng)
    end

    # Linux platform-specific platform object
    #
    # === Return
    # instance of Platform::Linux:: If ruby interpreter is running on Linux
    # nil:: Otherwise
    def linux
      raise PlatformError.new("Only available under Linux") unless linux?
      require_linux
      return Linux.new
    end

    def self.method_missing(meth, *args)
      if self.instance_methods.include?(meth.to_s)
        @@instance = self.new unless @@instance
        @@instance.send(meth, *args)
      else
        super
      end
    end

    private

    def require_linux
      require File.expand_path(File.join(File.dirname(__FILE__), 'platform', 'linux'))
    end

    def require_mac
      require File.expand_path(File.join(File.dirname(__FILE__), 'platform', 'darwin'))
    end

    def require_windows
      require File.expand_path(File.join(File.dirname(__FILE__), 'platform', 'windows'))
    end

    # Determines which cloud we're on by the cheap but simple expedient of
    # reading the RightScale cloud file.
    def resolve_cloud_type
      cloud_type = File.read(File.join(self.filesystem.right_scale_state_dir, 'cloud')) rescue nil
      @ec2 = false
      @rackspace = false
      @eucalyptus = false
      case cloud_type
        when 'ec2' then ec2 = true
        when 'rackspace' then @rackspace = true
        when 'eucalyptus' then eucalyptus = true
      end
    end

    # Retrieve platform specific service implementation
    #
    # === Parameters
    # name(Symbol):: Service name, one of :filesystem, :shell, :ssh, :controller
    #
    # === Return
    # res(Object):: Service instance
    #
    # === Raise
    # RightScale::Exceptions::PlatformError:: If the service is not known
    def platform_service(name)
      instance_var = "@#{name.to_s}".to_sym
      const_name = name.to_s.camelize

      unless res = self.instance_variable_get(instance_var)
        load_platform_specific
        if linux?
          res = Linux.const_get(const_name).new
        elsif mac?
          res = Darwin.const_get(const_name).new
        elsif windows?
          res = Windows.const_get(const_name).new
        end
        instance_variable_set(instance_var, res)
      end
      return res
    end

  end
end

end # Unless already defined
