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

module RightScale

  # Helper class used to initialize secure serializer
  class SecureSerializerInitializer

    # Initialize serializer
    #
    # === Parameters
    # agent_name<String>:: Name of agent used to build filename of certificate and key
    # identity<String>:: Agent identity
    # certs_dir<String>:: Path to directory containing agent private key and certificates
    #
    # === Return
    # true:: Always return true
    def self.init(agent_name, identity, certs_dir)
      cert = Nanite::Certificate.load(File.join(certs_dir, "#{agent_name}.cert"))
      key = Nanite::RsaKeyPair.load(File.join(certs_dir, "#{agent_name}.key"))
      mapper_cert = Nanite::Certificate.load(File.join(certs_dir, "mapper.cert"))
      store = Nanite::StaticCertificateStore.new(mapper_cert, mapper_cert)
      Nanite::SecureSerializer.init(identity, cert, key, store)
      true
    end

  end

end