#!/bin/bash
#
# Copyright (c) 2009-2011 RightScale Inc
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

#
# First figure out where the RightLink CLI tools actually
# live so we can generate stubs/wrappers that point to them.
#
fixed_path_guess=/opt/rightscale/right_link/bin
relative_path_guess=`dirname $0`

if [ -e $fixed_path_guess/setup.sh ]
then
  # This script was packaged and then deployed into /opt/rightscale
  right_scale_root="/opt/rightscale"
  right_link_root="${right_scale_root}/right_link"
elif [ -e $relative_path_guess ]
then
  # This script is running in out of a Git repository, e.g. on a developer machine
  pushd $relative_path_guess/.. > /dev/null
  right_link_root="$PWD"
  cd ..
  right_scale_root="$PWD"
  popd > /dev/null
else
  echo "Cannot infer location of bin dir from $0"
  echo "Please invoke this script using its absolute path."
  exit 1
fi

#
# Install RightLink gem dependencies
#
function install_gems() {
    echo "Installing RightLink gem dependencies"
    cd $right_link_root

    if [ -e /opt/rightscale/sandbox/bin/gem ]
    then
      # Use RightScale sandbox as our first choice
      gem_bin="/opt/rightscale/sandbox/bin/gem"
    elif [ -e /etc/profile.d/rvm.sh -a -e /usr/local/rvm/rubies/ruby-1.8.7-p352 ]
    then
      # Use RVM, if the Ruby we need is installed
      source /etc/profile.d/rvm.sh
      rvm use ruby-1.8.7-p352
      using_rvm=1
      gem_bin=`which gem`
    else
      # Fallback choice: use the system Ruby
      gem_bin=`which gem`
    fi

    $gem_bin install --no-rdoc --no-ri -v "~> 1.0.18" bundler | logger -st RightScale

    if [ -e /opt/rightscale/sandbox/bin/bundle ]
    then
      # The RightScale sandbox lives in a fixed location on disk. Use the sandbox
      # Ruby as our first choice, if it exists.
      bundle_bin="/opt/rightscale/sandbox/bin/bundle"
    elif [ "$using_rvm" == "" -a -e /var/lib/gems/1.8/bin/bundle ]
    then
      # Debian systems using the system Ruby package have a very odd location
      # for gem binaries!
      bundle_bin="/var/lib/gems/1.8/bin/bundle"
    else
      # Generic case; works for non-Debian system Ruby as well as for RVM
      bundle_bin=`which bundle`
    fi

    if [ -e vendor/cache ]
    then
        echo "Installing gems in release mode (local sources only)"
        bundle_flags="--local"
    else
        echo "Installing gems in development mode"
        bundle_flags=""
    fi

    cd $right_link_root
    $bundle_bin install $bundle_flags
}

#
# Create stub scripts for public RightLink tools
#
function install_public_wrappers() {
    public_wrapper_dir="/usr/bin"
    echo
    echo Installing public-tool wrappers to $public_wrapper_dir

    if [ ! -w "$public_wrapper_dir" ]
    then
      echo "Cannot install public-tool wrappers to $public_wrapper_dir"
      echo "Make sure the directory exists and is writable!"
      echo "Skipping public-tool wrappers; RightLink probably will not work except for tests."
      return 1
    fi

    for script in rs_run_right_script rs_run_recipe rs_log_level rs_reenroll rs_tag rs_shutdown rs_connect
    do
      echo " - $script"
      cat > $public_wrapper_dir/$script <<EOF
#!/bin/bash

target="${right_link_root}/bin/${script}.rb"

EOF
      cat >> $public_wrapper_dir/$script <<"EOF"
if [ -e /opt/rightscale/sandbox/bin/ruby ]
then
  ruby_bin="/opt/rightscale/sandbox/bin/ruby"
elif [ -e /etc/profile.d/rvm.sh -a -e /usr/local/rvm/rubies/ruby-1.8.7-p352 ]
then
  source /etc/profile.d/rvm.sh
  rvm use ruby-1.8.7-p352
  ruby_bin=`which ruby`
else
  ruby_bin=`which ruby`
fi

ruby_minor=`$ruby_bin -e "puts RUBY_VERSION.split('.')[1]"`
ruby_tiny=`$ruby_bin -e "puts RUBY_VERSION.split('.')[2]"`

if [ "$ruby_minor" -eq "8" -a "$ruby_tiny" -ge "7" ]
then
    exec $ruby_bin $target "$@"
else
  echo "The Ruby interpreter at $ruby_bin is not RightLink-compatible"
  echo "Ruby >= 1.8.7 and < 1.9.0 is required!"
  echo "This machine is running 1.${ruby_minor}.${ruby_tiny}"
  echo "Consider installing RVM to the system"
  exit 187
fi
EOF
      chmod a+x $public_wrapper_dir/$script
    done

    echo Done.
}

#
# Create stub scripts for private RightLink tools
# OPTIONAL - does not always happen, e.g. for development mode
#
function install_private_wrappers() {
    private_wrapper_dir="/opt/rightscale/bin"
    mkdir -p "$private_wrapper_dir" || true

    if [ ! -w "$private_wrapper_dir" ]
    then
      echo "Cannot install private-tool wrappers to $private_wrapper_dir"
      echo "Make sure the directory exists and is writable!"
      echo "Skipping private-tool wrappers; RightLink probably will not work except for tests."
      return 0
    fi

    echo
    echo Installing private-tool wrappers to $private_wrapper_dir
    for script in rad rchk rnac rstat cloud system enroll deploy
    do
      echo " - $script"
      cat > $private_wrapper_dir/$script <<EOF
#!/bin/bash
target="${right_link_root}/bin/${script}.rb"

EOF
      cat >> $private_wrapper_dir/$script <<"EOF"
if [ -e /opt/rightscale/sandbox/bin/ruby ]
then
  ruby_bin="/opt/rightscale/sandbox/bin/ruby"
elif [ -e /etc/profile.d/rvm.sh -a -e /usr/local/rvm/rubies/ruby-1.8.7-p352 ]
then
  source /etc/profile.d/rvm.sh
  rvm use ruby-1.8.7-p352
  ruby_bin=`which ruby`
else
  ruby_bin=`which ruby`
fi

ruby_minor=`$ruby_bin -e "puts RUBY_VERSION.split('.')[1]"`
ruby_tiny=`$ruby_bin -e "puts RUBY_VERSION.split('.')[2]"`

if [ "$ruby_minor" -eq "8" -a "$ruby_tiny" -ge "7" ]
then
    exec $ruby_bin $target "$@"
else
  echo "The Ruby interpreter at $ruby_bin is not RightLink-compatible"
  echo "Ruby >= 1.8.7 and < 1.9.0 is required!"
  echo "This machine is running 1.${ruby_minor}.${ruby_tiny}"
  echo "Consider installing the RightLink sandbox"
  exit 187
fi
EOF
      chmod a+x $private_wrapper_dir/$script
    done
}

install_gems || exit 1
echo
install_public_wrappers || exit 1
echo
install_private_wrappers || true
exit 0
