# Instance agent configuration
# Configuration values are listed with the format:
# name value

# Path to RightLink root folder
right_link_path File.expand_path(File.join(File.dirname(__FILE__), '..'))

# Path to directory containing the certificates used to sign and encrypt all
# outgoing messages as well as to check the signature and decrypt any incoming
# messages.
# This directory should contain at least:
#  - The instance agent private key ('instance.key')
#  - The instance agent public certificate ('instance.cert')
#  - The mapper public certificate ('mapper.cert')
certs_dir File.join(right_link_path, 'certs')