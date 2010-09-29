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

  # Proxy to actual certificate store which caches results in an LRU cache
  class CachedCertificateStoreProxy
    
    # Initialize cache proxy with given certificate store
    #
    # === Parameters
    # store(Object):: Certificate store responding to get_recipients and
    #   get_signer
    def initialize(store)
      @signer_cache = CertificateCache.new
      @store = store
    end

    # Retrieve recipient certificates
    # Results are not cached
    #
    # === Parameters
    # packet(RightScale::Packet):: Packet containing recipient identity, ignored
    #
    # === Return
    # (Array):: Recipient certificates
    def get_recipients(obj)
      @store.get_recipients(obj)
    end

    # Check cache for signer certificate
    #
    # === Parameters
    # id(String):: Serialized identity of signer
    #
    # === Return
    # (Array):: Signer certificates
    def get_signer(id)
      @signer_cache.get(id) { @store.get_signer(id) }
    end

  end # CachedCertificateStoreProxy

end # RightScale
