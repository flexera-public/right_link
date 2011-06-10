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

# clouds can specialize other clouds by extension.
extend_cloud :macleod

metadata_source 'metadata_sources/mock_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer'

# additionally search for extension scripts (relative to this script).
extension_script_base_paths '../scripts'

# constants can be declared which are local to the cloud instance (i.e. do not
# affect the shared Cloud class) and can be inherited when clouds are extended.
CLOUD_METADATA = {'ABC' => ['easy', 123], 'simple' => "do re mi", 'abc_123' => {'baby' => [:you, :me, :girl] }}
USER_METADATA = { 'RS_RN_ID' => '12345', 'RS_SERVER' => 'my.rightscale.com' }
METADATA = { CLOUD_METADATA_ROOT => CLOUD_METADATA, USER_METADATA_ROOT => USER_METADATA }

# options can be specific to the exact dependency type.
default_option([:metadata_source, :mock_metadata_source, :mock_metadata], METADATA)
