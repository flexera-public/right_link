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

  # Build X.509 compliant distinguished names
  # Distinguished names are used to describe both a certificate issuer and subject
  class DistinguishedName
    
    # Initialize distinguished name from hash
    # e.g.:
    #   { 'C'  => 'US',
    #     'ST' => 'California',
    #     'L'  => 'Santa Barbara',
    #     'O'  => 'RightScale',
    #     'OU' => 'Certification Services',
    #     'CN' => 'rightscale.com/emailAddress=cert@rightscale.com' }
    #
    def initialize(hash)
      @value = hash
    end
    
    # Conversion to OpenSSL X509 DN
    def to_x509
      if @value
        OpenSSL::X509::Name.new(@value.to_a, OpenSSL::X509::Name::OBJECT_TYPE_TEMPLATE)
      end
    end

    # Human readable form
    def to_s
      '/' + @value.to_a.collect { |p| p.join('=') }.join('/') if @value
    end
    
  end # DistinguishedName

end # RightScale
