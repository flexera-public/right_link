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

provides "ec2"

require_plugin "network"

if ::RightScale::CloudUtilities.is_cloud?(:ec2){ ::RightScale::CloudUtilities.has_mac?(self, "fe:ff:ff:ff:ff:ff") }
  if ::RightScale::CloudUtilities.can_contact_metadata_server?("169.254.169.254", 80)
    ec2 Mash.new
    ec2.update(::RightScale::CloudUtilities.metadata("http://169.254.169.254/2008-02-01/meta-data"))
    ec2[:userdata] = ::RightScale::CloudUtilities.userdata("http://169.254.169.254/2008-02-01/user-data")
  end
end

