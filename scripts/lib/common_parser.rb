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

require 'uri'
require 'tmpdir'

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common', 'agent', 'agent_identity'))

# Common options parser
module RightScale
  module CommonParser

    # Parse common options between rad and rnac
    def parse_common(opts, options)

      opts.on("--test") do 
        options[:user] = 'test'
        options[:pass] = 'testing'
        options[:vhost] = '/right_net'
        options[:test] = true
        options[:pid_dir] = Dir.tmpdir
        options[:base_id] = "#{rand(1000000)}"
        options[:options][:log_dir] = Dir.tmpdir
      end

      opts.on("-i", "--identity ID") do |id|
        options[:base_id] = id
      end

      opts.on("-t", "--token TOKEN") do |t|
        options[:token] = t
      end

      opts.on("-r", "--prefix PREFIX") do |p|
        options[:prefix] = p
      end

      opts.on("--url URL") do |url|
        uri = URI.parse(url)
        options[:user]  = uri.user     if uri.user
        options[:pass]  = uri.password if uri.password
        options[:host]  = uri.host
        options[:port]  = uri.port     if uri.port
        options[:vhost] = uri.path     if (uri.path && !uri.path.empty?)
      end
      
      opts.on("-u", "--user USER") do |user|
        options[:user] = user
      end

      opts.on("-p", "--pass PASSWORD") do |pass|
        options[:pass] = pass
      end

      opts.on("-v", "--vhost VHOST") do |vhost|
        options[:vhost] = vhost
      end

      opts.on("-P", "--port PORT") do |port|
        options[:port] = port
      end

      opts.on("-h", "--host HOST") do |host|
        options[:host] = host
      end

      opts.on('--alias ALIAS') do |a|
        options[:alias] = a
      end

      opts.on_tail("--help") do
        RDoc::usage_from_file(__FILE__)
        exit
      end

      opts.on_tail("--version") do
        puts version
        exit
      end
    end

    # Generate agent or mapper identity from options
    # Build identity from base_id, token, prefix and agent name
    #
    # === Parameters
    # options(Hash):: Hash containing identity components
    #
    # === Return
    # options(Hash)::
    def resolve_identity(options)
      if options[:base_id]
        base_id = options[:base_id].to_i
        if base_id.abs.to_s != options[:base_id]
          puts "** Identity needs to be a positive integer"
          exit(1)
        end
        name = options[:alias] || options[:agent] || 'mapper'
        puts "NAME: #{name}"
        token = options[:token]
        token = RightScale::SecureIdentity.derive(base_id, options[:token]) if options[:secure_identity]
        options[:identity] = AgentIdentity.new(options[:prefix] || 'rs', name, base_id, token).to_s
      end
    end

  end
end
