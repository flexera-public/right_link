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

require File.join(File.normalize_path(File.dirname(__FILE__)), 'ec2_metadata_provider_base')

module RightScale

  # Implements MetadataProvider for EC2.
  class EucaMetadataProvider < Ec2MetadataProvider

    protected

    # selects a host/port by attempting to dig the eucalyptus metadata server's
    # DNS name before falling back to EC2-style server. see
    # http://open.eucalyptus.com/participate/wiki/accessing-instance-metadata
    # for details.
    #
    # === Return
    # result(Array):: pair in form of [host, port]
    def select_metadata_server
      # resolve eucalyptus metadata server hostname
      addrs = Socket.gethostbyname('euca-metadata')[3..-1]

      # select only IPv4 addresses
      addrs = addrs.select { |x| x.length == 4 }

      # choose a random IPv4 address
      raw_ip = addrs[rand(addrs.size)]

      # transform binary IP address into string representation
      ip = []
      raw_ip.each_byte { |x| ip << x.to_s }
      host = ip.join('.')
      port = 8773
      return host, port
    rescue Exception
      # default to EC2 host,port
      super
    end

  end

end
