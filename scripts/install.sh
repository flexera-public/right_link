#!/bin/bash
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

if [ -d /opt/rightscale/right_link/scripts ]; then
	export RIGHT_NET_SCRIPTS=/opt/rightscale/right_link/scripts
else
	export RIGHT_NET_SCRIPTS=`pwd`
fi
echo Installing scripts from $RIGHT_NET_SCRIPTS
	rm -f /usr/bin/rnac
	rm -f /usr/bin/rad
	rm -f /usr/bin/rs_run_right_script
	rm -f /usr/bin/rs_run_recipe
	rm -f /usr/bin/rs_log_level
	rm -f /usr/bin/rs_reenroll
	rm -f /usr/bin/rs_tag
ln -s $RIGHT_NET_SCRIPTS/rnac.rb /usr/bin/rnac
chmod a+x $RIGHT_NET_SCRIPTS/rnac.rb
ln -s $RIGHT_NET_SCRIPTS/rad.rb /usr/bin/rad
chmod a+x $RIGHT_NET_SCRIPTS/rad.rb
ln -s $RIGHT_NET_SCRIPTS/rs_run_right_script.rb /usr/bin/rs_run_right_script
chmod a+x $RIGHT_NET_SCRIPTS/rs_run_right_script.rb
ln -s $RIGHT_NET_SCRIPTS/rs_run_recipe.rb /usr/bin/rs_run_recipe
chmod a+x $RIGHT_NET_SCRIPTS/rs_run_recipe.rb
ln -s $RIGHT_NET_SCRIPTS/rs_log_level.rb /usr/bin/rs_log_level
chmod a+x $RIGHT_NET_SCRIPTS/rs_log_level.rb
ln -s $RIGHT_NET_SCRIPTS/rs_reenroll.rb /usr/bin/rs_reenroll
chmod a+x $RIGHT_NET_SCRIPTS/rs_reenroll.rb
ln -s $RIGHT_NET_SCRIPTS/rs_tag.rb /usr/bin/rs_tag
chmod a+x $RIGHT_NET_SCRIPTS/rs_tag.rb
