#
# Copyright (c) 2010 RightScale Inc
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

module RightScale

  # Dynamically create Chef providers from Powershell scripts.
  # All the Powershell scripts defining a Chef provider should be contained in
  # a folder under the cookbook 'powershell_providers' directory. For
  # example creating an IIS Chef provider exposing a start web site and a stop
  # web site action in Powershell would involve creating the following file
  # hierarchy:
  #
  # `--iis_cookbook
  #    |-- metadata.json
  #    |-- metadata.rb
  #    |-- powershell_providers
  #    |   `-- iis
  #    |       |-- _init.ps1
  #    |       |-- _load_current_resource.ps1
  #    |       |-- start.ps1
  #    |       |-- stop.ps1
  #    |       `-- _term.ps1
  #    |-- recipes
  #    |   |-- default.rb
  #    |   |-- install.rb
  #    |   |-- restart.rb
  #    |   |-- start.rb
  #    |   `-- stop.rb
  #    `-- resources
  #        `-- iis.rb
  #
  # In this example, the 'start.rb', 'stop.rb' and 'restart.rb' recipes would
  # use the 'start' and/or 'stop' actions implemented by the corresponding
  # Powershell scripts.
  #
  # The '_init.ps1' and '_term.ps1' are optional scripts that can contain
  # initialization and cleanup code respectively. These two scripts are called
  # once during a single Chef converge and can be used e.g. to load required
  # .NET assemblies in the Powershell environment used to run the action
  # scripts.
  # The '_load_current_resource.ps1' script is also optional. Chef calls this
  # script right before executing an action if it exists. The script should
  # load any state from the system that the provider needs in order to run its
  # actions (in this example this script could check whether the website is
  # currently running so that the start and stop scripts would know whether any
  # action is required on their part).
  #
  # Note that there should be a light weight resource defined for each
  # Powershell provider. By default the resource name should match the name of
  # the provider (that is the name of the folder containing the Powershell
  # scripts). A lightweight resource can specify a different name for its
  # corresponding provider though.
  #
  # Typical usage for this class involved calling 'generate_providers' multiple
  # times then inspecting 'validation_errors'
  class DynamicPowershellProvider

    # Name of directory under cookbook that contains Powershell providers
    POWERSHELL_PROVIDERS_DIR_NAME = 'powershell_providers'

    # List of files with built-in behavior
    INIT_SCRIPT = '_init'
    TERM_SCRIPT = '_term'
    LOAD_SCRIPT = '_load_current_resource'
    BUILT_IN_SCRIPTS = [ INIT_SCRIPT, TERM_SCRIPT, LOAD_SCRIPT ]

    # Hash of Powershell Chef providers validation errors keyed by provider path and
    # initialized by 'generate_providers'
    attr_reader :validation_errors

    # Generated providers classes
    # initialized by 'generate_providers'
    attr_reader :providers

    # Initialize instance
    def initialize
      @validation_errors = {}
      @providers = []
      @providers_names = []
    end

    # Generate Chef providers from cookbooks in given path
    # Initializes 'validation_errors' accordingly
    # Skip providers that have already been created by this instance
    #
    # === Parameters
    # cookbooks_path(String|Array):: Path(s) to cookbooks directories
    #
    # === Return
    # providers(Array):: List of generated providers names
    def generate_providers(cookbooks_paths)
      providers = []
      cookbooks_paths = [ cookbooks_paths ] unless cookbooks_paths.is_a?(Array)
      cookbooks_paths.each do |cookbooks_path|
        return [] unless File.directory?(cookbooks_path)
        Dir[File.join(cookbooks_path, '*/')].each do |cookbook_path|
          cookbook = File.basename(cookbook_path).camelize
          Dir[File.join(cookbook_path, POWERSHELL_PROVIDERS_DIR_NAME, '*/')].each do |provider|
            name = "#{cookbook}::Powershell::#{File.basename(provider).camelize}"
            next if @providers_names.include?(name)
            generate_single_provider(name, provider)
            providers << name
          end
        end
      end
      @providers_names += providers
      true
    end

    protected

    # Dynamically create provider class
    #
    # === Parameters
    # name(String):: Powershell Chef provider class name
    # path(String):: Path to directory containing Powershell scripts
    #
    # === Return
    # true:: Always return true
    def generate_single_provider(name, path)
      RightLinkLog.debug("[chef] Creating Powershell provider #{name}")
      all_scripts = Dir[File.join(path, "*#{Platform::Windows::Shell::POWERSHELL_V1x0_SCRIPT_EXTENSION}")]
      action_scripts = all_scripts.select { |s| is_action_script?(s) }
      @providers << create_provider_class(name) do |provider|
        action_scripts.each do |script|
          action_name = 'action_' + File.basename(script, '.*').snake_case
          RightLinkLog.debug("[chef] Defining #{name}##{action_name} to run '#{script}'")
          provider.class_eval("def #{action_name}; #{name}.run_script('#{script}'); end")
        end
        if load_script = all_scripts.detect { |s| File.basename(s, '.*').downcase == LOAD_SCRIPT }
          RightLinkLog.debug("[chef] Defining #{name}#load_current_resource to run '#{load_script}'")
          provider.class_eval("def load_current_resource; #{name}.run_script('#{load_script}'); end")
        end
        if init_script = all_scripts.detect { |s| File.basename(s, '.*').downcase == INIT_SCRIPT }
          RightLinkLog.debug("[chef] Defining #{name}.init to run '#{init_script}'")
          provider.instance_eval("def init; super; run_script('#{init_script}'); end")
        end
        if term_script = all_scripts.detect { |s| File.basename(s, '.*').downcase == TERM_SCRIPT }
          RightLinkLog.debug("[chef] Defining #{name}.term to run '#{term_script}'")
          provider.instance_eval("def terminate; run_script('#{term_script}'); super; end")
        end
        RightLinkLog.debug("[chef] Done creating #{name}")
      end
      true
    end

    # Creates/overrides class with given name
    # Also create modules if class name includes '::' and corresponding
    # modules don't exist yet.
    #
    # === Parameters
    # name(String):: Class name, may include module names as well (e.g. 'Foo::Bar')
    # mod(Constant):: Module in which class should be created, Object by default
    #
    # === Block
    # Given block should take one argument which corresponds to the class instance
    def create_provider_class(name, mod=Object, &init)
      parts = name.split('::', 2)
      cls = nil
      if parts.size == 1
        if mod.const_defined?(name)
          # Was already previously defined, undef all the known methods
          cls = mod.const_get(name)
          cls.instance_eval('undef :init; undef :term')
          (cls.instance_methods - Chef::Provider.instance_methods).each { |m| cls.class_eval("undef #{m}") }
          init.call(cls)
        else
          # New class
          cls = Class.new(RightScale::PowershellProviderBase) { |c| init.call(c) }
          mod.const_set(name, cls)
        end
      else
        m = parts[0]
        mod = if mod.const_defined?(m)
          # Recurse into existing module
          mod.const_get(m)
        else
          # Create new module and recurse
          mod.const_set(m, Module.new)
        end
        cls = create_provider_class(parts[1], mod, &init)
      end
      cls
    end

    # Is given filename a valid Chef Powershell provider action script?
    #
    # === Parameters
    # filename(String):: File name to be tested
    #
    # === Return
    # true:: If given filename is a valid Powershell provider action script
    # false:: Otherwise
    def is_action_script?(filename)
      basename = File.basename(filename, '.*').downcase
      valid_identifier = !!(basename =~ /^[_|a-z]+[a-z|0-9|_]*$/)
      valid_identifier && !BUILT_IN_SCRIPTS.include?(basename)
    end

  end
end