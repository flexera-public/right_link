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
# First figure out where this script lives, which lets us infer
# where the Ruby scripts live (parallel to this script)
#
FIXED_PATH_GUESS=/opt/rightscale/right_link/scripts
ABSOLUTE_PATH_GUESS=`dirname $0`
if [ -e $FIXED_PATH_GUESS/install.sh ]
then
  SCRIPTS_DIR=$FIXED_PATH_GUESS
elif [ -e $ABSOLUTE_PATH_GUESS/install.sh ]
then
  pushd $ABSOLUTE_PATH_GUESS > /dev/null
  SCRIPTS_DIR=$PWD
  popd > /dev/null
else
  echo "Cannot determine path from $0"
  echo "Please invoke this script using its absolute path."
  exit 1
fi

#
# Next locate a Ruby interpreter
#
if [ -e /opt/rightscale/sandbox/bin/ruby ]
then
  RUBY_BIN=/opt/rightscale/sandbox/bin/ruby
elif [ ! -z `which ruby` ]
then
  RUBY_BIN=`which ruby`
elif [ ! -z $1 ]
then
  RUBY_BIN=$1
fi

if [ -z $RUBY_BIN ]
then
  echo "Can't locate Ruby interpreter! Run this script again and either:"
  echo " 1) ensure 'ruby' is in your path somewhere, or"
  echo " 2) supply the full path to 'ruby' as a cmd-line argument to this script"
  exit 1
fi

#
# Create private scripts for running all of the RightLink binaries
#
echo Installing scripts from $SCRIPTS_DIR...

echo Installing private scripts from $RIGHT_LINK_SCRIPTS ...
for script in rad rchk rnac rstat
do
  case "$script" in
    rad)   require="right_agent/scripts/agent_deployer"
           class=RightScale::AgentDeployer;;
    rnac)  require="right_agent/scripts/agent_controller"
           class=RightScale::AgentController;;
    rchk)  require="right_agent/scripts/agent_checker"
           class=RightScale::AgentChecker;;
    rstat) require="$SCRIPTS_DIR/mapper_stats_manager"
           class=RightScale::StatsManager;;
  esac
  echo Installing $script
  rm -f /opt/rightscale/bin/$script
  cat > /opt/rightscale/bin/$script <<EOF
#!/usr/bin/env ruby

# $script --help for usage information
#
# See $require.rb for additional information

require '$require'

\$stdout.sync=true

$class.run
EOF
  chmod a+x /opt/rightscale/bin/$script
done

#
# Finally, create stub scripts for all of the RightLink binaries
#
echo Installing command line tools from $SCRIPTS_DIR ...
for script in rs_run_right_script rs_run_recipe rs_log_level rs_reenroll rs_tag rs_shutdown rs_connect
do
  echo Installing $script
  cat > /usr/bin/$script <<EOF
#!/bin/bash
exec $RUBY_BIN $SCRIPTS_DIR/${script}.rb "\$@"
EOF
  chmod a+x /usr/bin/$script
done

echo Done.
