#!/bin/bash -e
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
# First figure out where the RightLink CLI scripts actually
# live so we can generate stubs/wrappers that point to them.
#
fixed_path_guess=/opt/rightscale/right_link/bin
relative_path_guess=`dirname $0`

if [ -e $fixed_path_guess/install.sh ]
then
  # This script was packaged and then deployed onto a cloud instance
  # Private-tool wrappers live into /opt/rightscale/bin
  BIN_DIR="$fixed_path_guess"
  PRIVATE_WRAPPER_DIR="/opt/rightscale/bin"
elif [ -e $relative_path_guess ]
then
  # This script is running in out of a Git repository, e.g. on a developer machine
  # Private-tool wrappers live in this dir, for lack of a better place to put them!
  pushd $relative_path_guess > /dev/null
  BIN_DIR="$PWD"
  popd > /dev/null
else
  echo "Cannot determine path from $0"
  echo "Please invoke this script using its absolute path."
  exit 1
fi

PUBLIC_WRAPPER_DIR="/usr/bin"

echo Creating wrappers for command-line tools in $BIN_DIR

#
# Create stub scripts for public RightLink tools
#
echo
echo Installing public-tool wrappers to $PUBLIC_WRAPPER_DIR
for script in rs_run_right_script rs_run_recipe rs_log_level rs_reenroll rs_tag rs_shutdown rs_connect
do
  echo " - $script"
  cat > $PUBLIC_WRAPPER_DIR/$script <<EOF
#!/bin/bash

target="$BIN_DIR/${script}.rb"

EOF
  cat >> $PUBLIC_WRAPPER_DIR/$script <<"EOF"
if [ -e /opt/rightscale/sandbox/bin/ruby ]
then
  ruby_bin="/opt/rightscale/sandbox/bin/ruby"
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
  chmod a+x $PUBLIC_WRAPPER_DIR/$script
done

echo Done.

#
# Create stub scripts for private RightLink tools
# OPTIONAL -- does not happen in development
#
if [ -z "$PRIVATE_WRAPPER_DIR" ]
then
  echo "Skipping private-tool wrappers since we are using relative paths"
  exit 0
fi

echo
echo Installing private-tool wrappers to $PRIVATE_WRAPPER_DIR
for script in rad rchk rnac rstat
do
  echo " - $script"
  cat > $PRIVATE_WRAPPER_DIR/$script <<EOF
#!/bin/bash
target="$BIN_DIR/${script}.rb"

EOF
  cat >> $PRIVATE_WRAPPER_DIR/$script <<"EOF"
if [ -e /opt/rightscale/sandbox/bin/ruby ]
then
  ruby_bin="/opt/rightscale/sandbox/bin/ruby"
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
  chmod a+x $PRIVATE_WRAPPER_DIR/$script
done
