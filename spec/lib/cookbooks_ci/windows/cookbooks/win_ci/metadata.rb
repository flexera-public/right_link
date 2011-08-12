maintainer       "RightScale, Inc."
maintainer_email "scott@rightscale.com"
license          IO.read(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'LICENSE')))
description      "Windows CI"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.rdoc'))
version          "0.3.8"

recipe "win_ci::default", "Sets up the Windows Continuous Integration box"

attribute 'win_ci/admin_password',
  :display_name => 'Windows CI administrator password',
  :description => 'Windows CI administrator password',
  :recipes => ["win_ci::default"],
  :required => true

attribute 'win_ci/tools_bucket',
  :display_name => 'Windows CI tools bucket URL',
  :description => 'S3 bucket containing public Windows CI tools to download.',
  :default => "http://smm-windows-continuous-integration.s3.amazonaws.com",
  :recipes => ["win_ci::default"]

attribute 'win_ci/projects',
  :display_name => 'Windows CI projects',
  :description => 'Projects to add to CCrb given as <name>=<repo url> pairs delimited by ampersand (&).',
  :default => "windows_ci_right_net=git@github.com:rightscale/right_net.git&windows_ci_sandbox_service=git@github.com:rightscale/win32_sandbox_service.git",
  :recipes => ["win_ci::default"]

attribute 'win_ci/credentials',
  :display_name => 'Windows CI credentials',
  :description => 'Private key credentials needed to checkout components for building.',
  :required => true,
  :recipes => ["win_ci::default"]

attribute 'win_ci/known_hosts',
  :display_name => 'Windows CI known hosts',
  :description => 'Known hosts text file content delimited by newlines.',
  :default => "github.com,207.97.227.239 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==",
  :recipes => ["win_ci::default"]

attribute "win_ci/dns_id",
  :display_name => "DNS id to register",
  :description => "DNS id (from DNS provider) to register for the current public IP",
  :recipes => ["win_ci::default"],
  :required => "required"

attribute "win_ci/dns_user",
  :display_name => "User name for DNS Made Easy",
  :description => "User name for DNS Made Easy HTTP request",
  :recipes => ["win_ci::default"],
  :required => "required"

attribute "win_ci/dns_password",
  :display_name => "Password for DNS Made Easy",
  :description => "Password for DNS Made Easy HTTP request",
  :recipes => ["win_ci::default"],
  :required => "required"

attribute "win_ci/dns_address_type",
  :display_name => "Type of address to register",
  :description => "Valid values are 'public' (default) or 'private'",
  :recipes => ["win_ci::default"],
  :required => "optional",
  :default => "public"
