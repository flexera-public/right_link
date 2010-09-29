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

# Helper methods used by scripts
# require and include the RightScale::Utils module
module RightScale

  module Utils

    # Path to RightLink root directory
    def root_path
      RightLinkConfig[:right_link_path]
    end

    # Path to directory containing generated agent configuration files
    def gen_dir
      File.join(root_path, 'generated')
    end
    
    # Path to given agent generated directory
    def gen_agent_dir(agent)
      File.join(gen_dir, agent)
    end

    # Path to actors source files
    def actors_dir
      File.join(root_path, 'actors', 'lib')
    end

    # Path to agents configuration files
    def agents_dir
      File.join(root_path, 'agents')
    end
    
    # Path to given agent directory
    def agent_dir(agent)
      File.join(agents_dir, agent)
    end

    # Path to cert folder
    def certs_dir
      File.normalize_path(File.join(root_path, '..', 'certs'))
    end
    
    # Path to scripts folder
    def scripts_dir
      File.join(root_path, 'scripts')
    end

    # Retrieve agent pid file from agent name (assume only one agent with that name running)
    def agent_pid_file(agent)
      root_dir = gen_agent_dir(agent)
      cfg = File.join(root_dir, 'config.yml')
      res = nil
      if File.readable?(cfg)
        options = symbolize(YAML.load(IO.read(cfg))) rescue nil
        if options
          agent = Agent.new(options)
          res = PidFile.new(agent.identity, agent.options)
        end
      end
      res
    end

    # Retrieve agent pid file from agent id and launch options
    def agent_pid_file_from_id(options, id)
      agent = Agent.new(options.merge(:agent_identity => id))
      PidFile.new(agent.identity, agent.options)
    end

    # Retrieve agent options from generated agent configuration file
    #
    # === Parameters
    # agent(String):: Name of agent
    #
    # === Return
    # options[:agent_identity](String):: Serialized agent identity
    # options[:log_path](String):: Log path
    # options[:pid](Integer):: Agent process pid if available
    # options[:listen_port](Integer):: Agent command listen port if available
    # options[:cookie](String):: Agent command cookie if available
    # options(Hash):: Other serialized configuration options
    def agent_options(agent)
      options = {}
      root_dir = gen_agent_dir(agent)
      if File.directory?(root_dir)
        cfg = File.join(root_dir, 'config.yml')
        if File.exists?(cfg)
          options = symbolize(YAML.load(IO.read(cfg))) rescue {} || {}
          options[:agent_identity] = options[:identity]
          options[:log_path] = options[:log_dir] || Platform.filesystem.log_dir
          pid_file = PidFile.new(options[:agent_identity], options)
          options.merge!(pid_file.read_pid) if pid_file.exists?
        end
      end
      options
    end
 
    # Produces a hash with keys as symbols from given hash
    def symbolize(h)
      sym = {}
      h.each do |key, val|
        nk = key.respond_to?(:intern) ? key.intern : key
        sym[nk] = val
      end
      sym
    end

  end
end
