#!/bin/bash
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
