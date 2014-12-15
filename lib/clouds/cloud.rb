#
# Copyright (c) 2011 RightScale Inc
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

require 'rubygems'
require 'extlib'
require 'ip'

module RightScale

  # Abstract base class for all clouds.
  class Cloud

    WILDCARD = :*

    # exceptions
    class CloudError < Exception; end

    attr_reader :name, :script_path, :options

    # Return type for any cloud action (e.g. write_metadata).
    class ActionResult
      attr_reader :error, :exitstatus, :output, :exception

      def initialize(options = {})
        @error = options[:error]
        @exception = options[:exception] || nil
        @exitstatus = options[:exitstatus] || 0
        @output = options[:output]
      end
    end

    # Initializer.
    #
    # === Parameters
    # options(Hash):: options grab bag used to configure cloud and dependencies.
    def initialize(options)
      raise ArgumentError.new("options[:name] is required") unless @name = options[:name]
      raise ArgumentError.new("options[:script_path] is required") unless @script_path = options[:script_path]

      # break options lineage and use Mash to handle keys as strings or tokens.
      # note that this is not a deep copy as :ohai is an option representing the
      # full ohai node in at least one use case.
      @options = options
    end

    # Syntatic sugar for options[:logger], which should always be valid under
    # normal circumstances.
    def logger; @options[:logger]; end

    # Cloud abbrevation. Normally used as a prefix for writing values out ot disk
    def abbreviation(value = nil)
      self.to_s.upcase
    end

    # Cloud name. Used to dynamically read in extension scripts.
    def self.cloud_name
      self.to_s.split("::").last.downcase
    end

    # Convenience methods, define userdata in terms of userdata_raw
    def userdata
      RightScale::CloudUtilities.parse_rightscale_userdata(userdata_raw)
    end

    # Finish function that's called when to pass to cloud if fetching metadata leads to any open
    # resources. No-op by default, up to each cloud to implement details.
    #
    # === Parameters
    # cloud_name(String|Token): name of cloud to extend
    #
    # === Return
    # always true
    #
    # === Raise
    # UnknownCloud:: on failure to find extended cloud
    def finish
      true
    end

    # Base paths for external scripts which extend methods of cloud object.
    # Names of scripts become instance methods and can override the predefined
    # cloud methods. The factory defaults to using any scripts in
    # "<rs_root_path>/bin/<cloud alias(es)>" directories.
    def extension_script_base_paths(*args)
      @extension_script_base_paths ||= []
      args.each do |path|
        path = relative_to_script_path(path)
        @extension_script_base_paths << path unless @extension_script_base_paths.include?(path)
      end
      @extension_script_base_paths
    end


    # Determines if the current instance is running on the cloud which require
    # additional network configuration(e.g. vsphere)
    #
    # === Return
    # result(Boolean):: true if current cloud require additional network configuration, false otherwise
    def requires_network_config?
      false
    end

    # Convenience method for failing to load or execute cloud definition.
    #
    # === Parameters
    # message(String):: message
    #
    # === Raise
    # always CloudError
    def fail(message)
      raise CloudError.new(message)
    end

    # Convenience method for getting information about the current machine
    # platform.
    #
    # === Return
    # result(Boolean):: true if windows
    def platform
      ::RightScale::Platform
    end

    # Queries and writes current metadata to file.
    #
    # === Parameters
    # kind(Symbol):: kind of metadata must be one of [:cloud_metadata, :user_metadata, WILDCARD]
    #
    # === Return
    # result(ActionResult):: action result
    def write_metadata(kind = WILDCARD)
      options = @options.dup

      kind = kind.to_sym
      if kind == WILDCARD || kind == :user_metadata

        # Both "blue-skies" cloud and "wrap instance" behave the same way, they lay down a
        # file in a predefined location (/var/spool/rightscale/user-data.txt on linux,
        # C:\ProgramData\RightScale\spool\rightscale\user-data.txt on windows. In both
        # cases this userdata has *lower* precedence than cloud data. On a start/stop
        # action where userdata is updated, we want the NEW userdata, not the old. So
        # if cloud-based values exists, than we always use those.
        cloud_userdata = userdata
        cloud_userdata_raw = userdata_raw

        source = RightScale::MetadataSources::RightScaleApiMetadataSource.new(options)
        if source.source_exists?
          unless cloud_userdata.keys.find { |k| k =~ /RS_rn_id/i }
            extra_userdata_raw = source.get()
            extra_userdata = RightScale::CloudUtilities.parse_rightscale_userdata(extra_userdata_raw)
            cloud_userdata = extra_userdata
            cloud_userdata_raw = extra_userdata_raw
          end
        end

        # Raw userdata is a special exception. We could reform the raw
        # string from the hash but why not pass it directly to preserve it exactly
        # and be a bit anal. 
        raw_writer = metadata_writers(:user_metadata).find { |writer| writer.kind_of?(RightScale::MetadataWriters::RawMetadataWriter) }
        raw_writer.write(cloud_userdata_raw)
        unless cloud_userdata.empty?
          metadata_writers(:user_metadata).each { |writer| writer.write(cloud_userdata) }
        end
      end
      if kind == WILDCARD || kind == :cloud_metadata
        cloud_metadata = metadata
        unless cloud_metadata.empty?
          metadata_writers(:cloud_metadata).each { |writer| writer.write(cloud_metadata) }
        end
      end
      return ActionResult.new
    rescue Exception => e
      return ActionResult.new(:exitstatus => 1, :error => "ERROR: #{e.message}", :exception => e)
    ensure
      finish()
    end

    # Convenience method for writing only cloud metdata.
    def write_cloud_metadata; write_metadata(:cloud_metadata); end

    # Convenience method for writing only user metdata.
    def write_user_metadata; write_metadata(:user_metadata); end


    # Attempts to clear any files generated by writers.
    #
    # === Return
    # always true
    #
    # === Raise
    # CloudError:: on failure to clean state
    def clear_state
      output_dir_paths = []
      [:user_metadata, :cloud_metadata].each do |kind|
        output_dir_paths |= metadata_writers(kind).map { |w| w.output_dir_path }
      end

      last_exception = nil
      output_dir_paths.each do |output_dir_path|
        begin
          FileUtils.rm_rf(output_dir_path) if File.directory?(output_dir_path)
        rescue Exception => e
          last_exception = e
        end
      end
      fail(last_exception.message) if last_exception
      return ActionResult.new
    rescue Exception => e
      return ActionResult.new(:exitstatus => 1, :error => "ERROR: #{e.message}", :exception => e)
    end

    # Gets the option given by path, if it exists.
    #
    # === Parameters
    # kind(Symbol):: :user_metadata or :cloud_metadata
    # === Return
    # result(Array(MetadataWriter)):: responds to write
    def metadata_writers(kind)
      return @metadata_writers[kind] if @metadata_writers && @metadata_writers[kind]
      @metadata_writers ||= {}
      @metadata_writers[kind] ||= []
  
      options = @options.dup
      options[:kind] = kind
      if kind == :user_metadata
        options[:formatted_path_prefix] = "RS_"
        options[:output_dir_path] ||= RightScale::AgentConfig.cloud_state_dir
        options[:file_name_prefix] = "user-data" 
      elsif kind == :cloud_metadata
        options[:formatted_path_prefix] = "#{abbreviation.upcase}_"
        options[:output_dir_path] ||= RightScale::AgentConfig.cloud_state_dir
        options[:file_name_prefix] = "meta-data" 
      end

      begin
        writers_dir_path = File.join(File.dirname(__FILE__), 'metadata_writers')

        # dynamically register all clouds using the script name as cloud name.
        pattern = File.join(writers_dir_path, '*.rb')
        Dir[pattern].each do |writer_script_path|
          writer_name = File.basename(writer_script_path, '.rb')
          require writer_script_path
          writer_class_name = writer_name.split(/[_ ]/).map {|w| w.capitalize}.join
          writer_class = eval("RightScale::MetadataWriters::#{writer_class_name}")
          @metadata_writers[kind] << writer_class.new(options)
        end
      end
      @metadata_writers[kind]
    end


    # Assembles the command line needed to regenerate cloud metadata on demand.
    def cloud_metadata_generation_command
      ruby_path = File.normalize_path(AgentConfig.ruby_cmd)
      rs_cloud_path = File.normalize_path(Gem.bin_path('right_link', 'cloud'))
      return "#{ruby_path} #{rs_cloud_path} --action write_cloud_metadata"
    end

    protected


    # Called internally to execute a cloud extension script with the given
    # command-line arguments, if any. It is generally assumed scripts will not
    # exit until finished and will read any instance-specific information from
    # the system or from the output of write_metadata.
    #
    # === Parameters
    # script_path(String):: path to script to execute
    # arguments(Array):: arguments for script command line or empty
    #
    # === Return
    # result(ActionResult):: action result
    def execute_script(script_path, *arguments)
      # If we are running a ruby script, use our own interpreter
      if File.extname(script_path) == '.rb'
        cmd = ::RightScale::Platform.shell.format_executable_command(
          RightScale::AgentConfig.ruby_cmd,
          *([script_path] + arguments))
      else
        cmd = ::RightScale::Platform.shell.format_shell_command(
          script_path,
          *arguments)
      end
      output = `#{cmd}`
      return ActionResult.new(:exitstatus => $?.exitstatus, :output => output)
    rescue Exception => e
      return ActionResult.new(:exitstatus => 1, :error => "ERROR: #{e.message}", :exception => e)
    end

    # make the given path relative to this cloud's DSL script path only if the
    # path is not already absolute.
    #
    # === Parameters
    # path(String):: absolute or relative path
    #
    # === Return
    # result(String):: absolute path
    def relative_to_script_path(path)
      path = path.gsub("\\", '/')
      unless path == File.expand_path(path)
        path = File.normalize_path(File.join(File.dirname(@script_path), path))
      end
      path
    end

  end  # Cloud

end  # RightScale
