RightScale vScale RightImage
============================

Below are some considerations for successfully launching vScale image in private network environments

These notes apply to: RightImage_CentOS_6.4_x64_v13.5.1_Beta_Dev6_4GB_79689a80c31f31

NTP Timeserver
==============

RightScale RightImages have NTP pre-configured with public timeservers. On private networks these timeservers will likely not be reachable. As long as your host system (hypervisor) is within a few minutes of the RightScale brokers, rightlink will enroll and boot correctly.  It is highly recommended to run an NTP client on your host systems (hypervisors).

NTP Servers Input
-----------------
To avoid clock drift over time, the RightScale ServerTemplates reconfigure the NTP client on boot. Be certain to set the "NTP Servers" input on your server to a locally routable NTP server.  There is also an NTP server provided by RightScale in the "island" that serves your cloud.  To use this timeserver, set the "NTP Servers" input to the FQDN of the RightScale "island" (i.e. "island10.rightscale.com"), which can be found the the Firewall Rules" report for your cloud.

DHCP Server
===========

RightImages are pre-configured to use dhcp to assign IP address.  If there is no DHCP server on your private network, you can have RightLink configure a Static IP by adding special userdata options to your server.  However, since rightlink starts after your network in initialized, you will see a delay in your boot sequence as the dhcp client times out waiting for a response.

Static IP Configuration Options
-------------------------------

Configures a static IP address for a given network interface,

 * `metadata:rs_static_ip0_addr` : IP address to assign
 * `metadata:rs_static_ip0_netmask` : Network mask (i.e. 255.255.255.0)
 * `metadata:rs_static_ip0_nameservers` : Comma-separated string of nameserver IP addresses.
 * `metadata:rs_static_ip0_gateway` : (optional) IP address of the gateway
 * `metadata:rs_static_ip0_device` : (optional) changes device name to configure. default: "eth0"

Setting User Data
=================
To set user-data for a given server, navigate the "next" server your server's [History Timeline](http://support.rightscale.com/12-Guides/Lifecycle_Management/05_-_Server_Management/Server_History_Timeline), click the "Edit" button, then "Advanced Options" where you will find the "User data" field.  The user-data must be entered as a single string of key=value pairs, that are separated by '&' characters.

Example:

	metadata:rs_static_ip0_addr=10.54.252.234&metadata:rs_static_ip0_netmask=255.255.255.224&metadata:rs_static_ip0_gateway=10.54.252.225&metadata:rs_static_ip0_nameservers=8.8.8.8,8.8.4.4


Known Limitations
=================
 * When setting a Static IP, there will be a delay in the boot sequence as the dhcp client times out waiting for a response.
 * RightImages have ntpd pre-configured for public servers, there may be some warning in logs until the boot recipes configure NTP
 * Only configures one device for a static IP -- typically used for private network interfaces.
 * RightLink "patching" mechanism has been disabled to avoid production patches accidentally being applied to this beta image.
 * Only manages and reporta up to two (2) network interfaces.
 * Detection of private networks is limited to well-known subnets as defined in [RFC-1918](https://tools.ietf.org/html/rfc1918):
   * 10.0.0.0, 192.168.0.0, 172.16.0.0, 172.2.0.0, 172.30.0.0 and 172.31.0.0
 * On VMs with two network interfaces. The second device will always be reported as private.
 * There is [CentOS issue](http://www.cyberciti.biz/tips/vmware-linux-lost-eth0-after-cloning-image.html) when cloning a VM to an image. Be certain to run the following command before cloning any CentOS VM to an image:

		`rm -f /etc/udev/rules.d/70-persistent-net.rules`

Troubleshooting
---------------
 * `metadata:rs_breakpoint=init_cloud_state` : will stop rightlink startup right after cloud definition file is executed.  This is useful for halting rightlink before "phoning home" which will allow one to login to the system and diagnose any networking problems.


----

Internal Features
=================

NAT Routing Options
-------------------

Sets up private network egress to external networks via a NAT server

 * `metadata:rs_nat_address` : IP address for the NAT server
 * `metadata:rs_nat_ranges`  : Comma-separated string of CIDR addresses to route though NAT server

NOTE: This will be set by the vScale adapter

Specifying an Island
--------------------

 * `metadata:rs_island` : used to specify the island affinity to use for mirror and patch urls. This value is the hostname for the island reverse proxy (i.e. "island10").  Default is "mirror".  To use the default on a private network you must have a route to mirror.rightscale.com.

NOTE: This will be set by the vScale adapter



NOTE: This must be set in the userdata by hand.

Test Suggestions
================

 1. public interface with DHCP
	* should go operational
	* public IP should be reported correctly in server info tab
	* recipes should have `node[:cloud][:provider] == "vsphere"`
	* recipes should have `node[:cloud][:public_ips].include?(public_ip)`
 2. private interface with DHCP
     * you will need to set up correct values for `metadata:rs_nat_ranges`
	 * should go operational (you will need correct nat_routes from above)
	 * private IP should be reported correctly in server info tab
     * recipes should have `node[:cloud][:private_ips].include?(private_ip)`
 3. private interface with Static IP (use userdata tags fromabove)
	 * should go operational
	 * public IP should be reported correctly in server info tab
     * recipes should have `node[:cloud][:private_ips].include?(private_ip)`
 4. both public and private interfaces
	 * should go operational
	 * IPs should be reported correctly in server info tab
	 * recipes should have `node[:cloud][:public_ips].include?(public_ip)`
     * recipes should have `node[:cloud][:private_ips].include?(private_ip)`


TODO (after Nexon installation)
====
 * overwrite NTP server config with `RS_ISLAND` unless `RS_NTP` is defined.
 * window support
 * ubuntu support
 * SUSE support
 * add static IP support for `rs_static_ip1` through `rs_static_ipN` and remove `rs_static_ip0_device` option

CHANGES
=======

v0.3
----
 * initial release. Built into dev3 CentOS image.

v0.4
----
 * added `VSCALE_DEFINITION_VERSION` to correlate with these changes
 * change the metadata prefix from vs_ to rs_
 * made `metadata:rs_static_ip0_gateway` optional
 * NAT routes now persist after a network restart
 * misc code cleanup

v0.5
----
 * fixed example userdata in readme
 * improved error handling
 * changes to init scripts for breakpoint support
 * changes to init scripts to skip patching if no route exists
 * added support for rs_island to fixing hard-coded URLs in init-scripts
 * disabled rightlink patching to avoid possible corruption of PoC image

v0.6
----
 * fixed how ohai node[:cloud] gets populated for scripts and recipes

