#
# Copyright (c) 2012 RightScale Inc
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

# Location for injected certificate
CERT_FILE = '/var/lib/waagent/Certificates.pem'

# Windows changes the ST=CA portion of our issuer name to S=CA at some point.
ISSUER_STATE_KEY = platform.windows? ? 'S' : 'ST'

# dependencies.
metadata_source 'metadata_sources/certificate_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer',
                 'metadata_writers/ruby_metadata_writer',
                 'metadata_writers/shell_metadata_writer'

# set abbreviation for non-RS env var generation
abbreviation :waz

# Parses azure user metadata into a hash.
#
# === Parameters
# tree_climber(MetadataTreeClimber):: tree climber
# data(String):: raw data
#
# === Return
# result(Hash):: Hash-like leaf value
def create_user_metadata_leaf(tree_climber, data)
  result = tree_climber.create_branch
  ::RightScale::CloudUtilities.split_metadata(data.strip, '&', result)
  result
end

# defaults.
default_option([:metadata_source, :user_metadata_cert_store], platform.windows? ? "cert:/LocalMachine/My" : CERT_FILE)
default_option([:metadata_source, :user_metadata_cert_issuer], "O=RightScale, C=US, #{ISSUER_STATE_KEY}=CA, CN=RightScale User Data")

default_option([:user_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))

def wait_for_instance_ready
  if platform.linux?
    STDOUT.puts "Waiting for instance to appear ready."
    until File.exist?(CERT_FILE) && File.mtime(CERT_FILE).to_f > platform.shell.booted_at.to_f do
      sleep(1)
    end
    STDOUT.puts "Instance appears ready."
  end
end

# Determines if the current instance is running on azure.
#
# === Return
# true if running on azure
def is_current_cloud?
  # FIX: the presence of the user data cert isn't sufficient criteria to
  # determine whether this is an azure instance. is there a mac address we can
  # check against? in the meantime, just say no.
  false
end

# Updates the given node with azure details.
#
# === Return
# always true
def update_details
  details = {}
  if ohai = @options[:ohai_node]
    # FIX: there is currently no instance-facing API (i.e. an API which does not
    # require management credentials) to provide the instance's public IP address
    # so a workaround is required until the instance-facing API is available.
    if public_ip = ::RightScale::CloudUtilities.query_whats_my_ip(:logger=>logger)
      details[:public_ip] = public_ip
    end
    if platform.windows?
      interface_names = ['Local Area Connection', # Windows Server 2008 R2
                         'Ethernet']              # Windows Server 2012+ (?)
      interface_names.each do |interface_name|
        if ip = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, interface_name)
          details[:private_ip] = ip
          break
        end
      end
    else
      details[:private_ip] = ::RightScale::CloudUtilities.ip_for_interface(ohai, :eth0)
    end
  end
  return details
end
