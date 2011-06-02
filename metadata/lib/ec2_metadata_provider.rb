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

begin
  this_path = File.normalize_path(File.dirname(__FILE__))
  require File.join(this_path, 'metadata_provider_base')
  require File.join(this_path, 'http_metadata_source')
  require File.join(this_path, 'metadata_tree_climber')
end

module RightScale

  # Implements MetadataProvider for EC2.
  class Ec2MetadataProvider < MetadataProviderBase

    def initialize(options)
      # defaults.
      options = options.dup
      if options[:cloud_metadata_root_path].nil?
        host, port = select_metadata_server
        options[:cloud_metadata_root_path] = "http://#{host}:#{port}/latest/meta-data"
        options[:user_metadata_root_path] = "http://#{host}:#{port}/latest/user-data"
      end
      options[:metadata_source] ||= HttpMetadataSource.new(options)

      options[:cloud_metadata_tree_climber] ||= MetadataTreeClimber.new(:tree_class => options[:tree_class],
                                                                        :root_path => options[:cloud_metadata_root_path])
      options[:user_metadata_tree_climber] ||= MetadataTreeClimber.new(:has_children_callback => lambda{ false } )

      # super.
      super(options)
    end

    protected

    # host/port are constants for EC2.
    HOST = '169.254.169.254'
    PORT = 80

    # Provides default host and port for EC2 metadata server.
    #
    # === Return
    # result(Array):: pair in form of [host, port]
    def select_metadata_server
      return HOST, PORT
    end

  end

end
