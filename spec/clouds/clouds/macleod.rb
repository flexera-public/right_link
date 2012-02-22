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

# additionally search custom dependency base path (relative to this script).
dependency_base_paths '..'

metadata_source 'metadata_sources/mock_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer'

# all options are specific to the category of dependency.
default_option(%w(metadata_tree_climber create_leaf_override), lambda{ |_, data| data })

# options can be further distinguished between cloud and user metadata
# or can be used by both if kind is not specified (as in the
# mock_metadata_source example).
CLOUD_METADATA_ROOT = 'cloud metadata'
USER_METADATA_ROOT = 'user metadata'

default_option('cloud_metadata/metadata_tree_climber/root_path', CLOUD_METADATA_ROOT)
default_option('user_metadata/metadata_tree_climber/root_path', USER_METADATA_ROOT)

# test logger.
logger.info("initialized MacLeod")
