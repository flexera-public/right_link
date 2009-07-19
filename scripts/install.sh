#!/bin/bash
if [ -d /opt/rightscale/nanite/scripts ]; then
	export RIGHT_NET_SCRIPTS=/opt/rightscale/nanite/scripts
else
	export RIGHT_NET_SCRIPTS=`pwd`
fi
echo Installing scripts from $RIGHT_NET_SCRIPTS
	rm -f /usr/bin/rnac
	rm -f /usr/bin/rad
	rm -f /usr/bin/rs_run_right_script
	rm -f /usr/bin/rs_run_recipe
ln -s $RIGHT_NET_SCRIPTS/rnac.rb /usr/bin/rnac
chmod a+x $RIGHT_NET_SCRIPTS/rnac.rb
ln -s $RIGHT_NET_SCRIPTS/rad.rb /usr/bin/rad
chmod a+x $RIGHT_NET_SCRIPTS/rad.rb
ln -s $RIGHT_NET_SCRIPTS/rs_run_right_script.rb /usr/bin/rs_run_right_script
chmod a+x $RIGHT_NET_SCRIPTS/rs_run_right_script.rb
ln -s $RIGHT_NET_SCRIPTS/rs_run_recipe.rb /usr/bin/rs_run_recipe
chmod a+x $RIGHT_NET_SCRIPTS/rs_run_recipe.rb
