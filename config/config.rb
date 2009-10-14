# Instance agent configuration
# Configuration values are listed with the format:
# name value

# Root path to RightScale files
rs_root_path File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))

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

# Configure RightLink sandbox (incl Ruby interpreter, RubyGems, etc)
# The sandbox enhances the robustness of the RightLink agent by including
# everything necessary to run the agent independently of any OS packages
# that may be installed. Using the sandbox is optional under Linux/Darwin.
sandbox_path File.join(rs_root_path, 'sandbox')
if platform.windows?
  raise StandardError.new("Missing sandbox; cannot proceed under Win32") unless File.directory?(sandbox_path)
  sandbox_ruby_cmd File.join(sandbox_path, 'Ruby', 'bin', 'ruby.exe')
  sandbox_gem_cmd  File.join(sandbox_path, 'Ruby', 'bin', 'gem.bat')
  sandbox_git_cmd  File.join(sandbox_path, 'Git',  'bin', 'git.cmd')
else
  if File.directory?(sandbox_path)
    sandbox_ruby_cmd File.join(sandbox_path, 'bin', 'ruby')
    sandbox_gem_cmd  File.join(sandbox_path, 'bin', 'gem')
    sandbox_git_cmd  File.join(sandbox_path, 'bin', 'git')
  else
    sandbox_ruby_cmd `which ruby`
    sandbox_gem_cmd  `which gem`
    sandbox_git_cmd  `which git`
  end
end
