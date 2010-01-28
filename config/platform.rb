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

# note that the plaform-specific submodules will be loaded on demand to resolve
# some install-time gem dependency issues.

module RightScale
  class PlatformError < StandardError; end

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
    # Initialize platform values
    def initialize
      @windows = !!(RUBY_PLATFORM =~ /mswin/)
      @mac     = !!(RUBY_PLATFORM =~ /darwin/)
      @linux   = !!(RUBY_PLATFORM =~ /linux/)

      @filesystem = nil
      @shell      = nil
      @ssh        = nil

      #Determine which cloud we're on by the cheap but simple expedient of reading
      #the RightScale cloud file.
      cloud_type = File.read(File.join(self.filesystem.right_scale_state_dir, 'cloud')) rescue nil
      case cloud_type
        when 'ec2':        @ec2 = true
        when 'rackspace':  @rackspace = true
        when 'eucalyptus': @eucalyptus = true
      end
    end

    # An alias for RUBY_PLATFORM
    #
    # === Return
    # name<String>:: RUBY_PLATFORM
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
      @ec2
    end

    # Are we in a Rackspace cloud?
    #
    # === Return
    # true:: If machine is located in an EC2 cloud
    # false:: Otherwise
    def rackspace?
      @rackspace
    end

    # Are we in a Eucalyptus cloud?
    #
    # === Return
    # true:: If machine is located in an EC2 cloud
    # false:: Otherwise
    def eucalyptus?
      @eucalyptus
    end

    # Filesystem config object
    #
    # === Return
    # fs<Filesystem>:: Platform-specific filesystem config object
    def filesystem
      if @filesystem.nil?
        if linux?
          require_linux
          @filesystem = Linux::Filesystem.new
        elsif mac?
          require_mac
          @filesystem = Darwin::Filesystem.new
        elsif windows?
          require_windows
          @filesystem = Win32::Filesystem.new
        else
          raise PlatformError.new("Don't know about the filesystem on this platform")
        end
      end
      return @filesystem
    end

    # Shell information object
    #
    # === Return
    # platform specific shell information object
    def shell
      if @shell.nil?
        if linux?
          require_linux
          @shell = Linux::Shell.new
        elsif mac?
          require_mac
          @shell = Darwin::Shell.new
        elsif windows?
          require_windows
          @shell = Win32::Shell.new
        else
          raise PlatformError.new("Don't know about the shell on this platform")
        end
      end
      return @shell
    end

    # SSH information object
    #
    # === Return
    # platform specific ssh object
    def ssh
      if @ssh.nil?
        if linux?
          require_linux
          @ssh = Linux::SSH.new(self)
        elsif mac?
          require_mac
          @ssh = Darwin::SSH.new(self)
        elsif windows?
          require_windows
          @ssh = Win32::SSH.new(self)
        else
          raise PlatformError.new("Don't know about the SSH on this platform")
        end
      end
      return @ssh
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
        self.new.send(meth, *args)
      else
        super(*args)
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
      require File.expand_path(File.join(File.dirname(__FILE__), 'platform', 'win32'))
    end

  end
end
