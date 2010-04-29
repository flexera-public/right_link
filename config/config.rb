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

# Instance agent configuration
# Configuration values are listed with the format:
# name value

# Root path to RightScale files
rs_root_path File.normalize_path(File.join(File.dirname(__FILE__), '..', '..'))

# Current RightLink protocol version
protocol_version 8

# Path to RightLink root folder
right_link_path File.join(rs_root_path, 'right_link')

# Path to directory containing the certificates used to sign and encrypt all
# outgoing messages as well as to check the signature and decrypt any incoming
# messages.
# This directory should contain at least:
#  - The instance agent private key ('instance.key')
#  - The instance agent public certificate ('instance.cert')
#  - The mapper public certificate ('mapper.cert')
certs_dir File.join(rs_root_path, 'certs')

# Path to directory containing persistent RightLink agent state.
agent_state_dir platform.filesystem.right_scale_state_dir

# Path to directory containing transient cloud-related state (metadata, userdata, etc).
cloud_state_dir File.join(platform.filesystem.spool_dir, 'cloud')

# This logic is duplicated in right_link_install_gems.rb which cannot use
# this file due to chicken-and-egg problems with mixlib-config. If you change it
# here, please change it there and vice-versa.
if platform.windows?
  # note that we cannot use the provided windows gem.bat because it pulls any
  # ruby.exe on the PATH instead of using the companion ruby.exe from the same
  # bin directory.
  candidate_path = File.join(platform.filesystem.company_program_files_dir, 'SandBox')
  if File.directory?(candidate_path)
    sandbox_path candidate_path
    sandbox_ruby_cmd File.join(sandbox_path, 'Ruby', 'bin', 'ruby.exe')
    # We need to specify the path to the ruby interpreter we need to use as the gem implementation
    # on Windows will pick whichever ruby is in the path
    sandbox_gem_cmd  "\"#{sandbox_ruby_cmd}\" \"#{File.join(sandbox_path, 'Ruby', 'bin', 'gem.exe')}\""
    sandbox_git_cmd  File.join(sandbox_path, 'bin', 'windows', 'git.cmd')
  else
    # Development setup
    sandbox_path nil
    sandbox_ruby_cmd 'ruby'
    sandbox_gem_cmd  'gem'
    sandbox_git_cmd  'git'
  end
else
  candidate_path = File.join(rs_root_path, 'sandbox')
  if File.directory?(candidate_path)
    sandbox_path candidate_path
    sandbox_ruby_cmd File.join(sandbox_path, 'bin', 'ruby')
    sandbox_gem_cmd  File.join(sandbox_path, 'bin', 'gem')
    sandbox_git_cmd  File.join(sandbox_path, 'bin', 'git')
  else
    # Development setup
    sandbox_path nil
    sandbox_ruby_cmd `which ruby`.chomp
    sandbox_gem_cmd  `which gem`.chomp
    sandbox_git_cmd  `which git`.chomp
  end
end
