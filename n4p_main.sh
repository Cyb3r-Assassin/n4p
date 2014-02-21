#!/bin/bash

##############################################
# Do all prerun variables and safty measures #
# before anything else starts happening      #
##############################################
if [[ $(id -u) != 0 ]]; then # Verify we are root if not exit
   echo "Please Run This Script As Root or With Sudo!" 1>&2
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
        echo "Useage: n4p [mode] [option] [option [eth0 wlan0]]
        where: mode
            -a              Airbase-ng as AP
            --airbase-ng    Airbase-ng as AP
            -h              Hostapd as AP
            --hostapd       Hostapd as AP
        Where: option 1
            -b              Bridged mode
            --bridge        Bridged mode
            -d              DHCPD enabled
            --dhcpd         DHCPD enabled
        Where: option 2
            -i              Use interfaces"
        exit 0
    # If any fast options were used predefine there variables now
    elif [[ $1 == '-a' || $1 == '--airbase-ng' ]]; then
        FAST="True"
        FAST_AIRBASE="True"
    elif [[ $1 == '-h' || $1 == '--hostapd' ]]; then
        FAST="True"
        FAST_HOSTAPD="True"
    else
        echo "Invalid option at '$1' see --help"
        exit 0
    fi

    if [[ -n $2 ]]; then
        if [[ $2 == '-b' || $2 == '--bridge' ]]; then
            BRIDGED="True"
        elif [[ $2 == '-d' || $2 == '--dhcpd' ]]; then
            BRIDGED="False"
        else
            echo "Invalid option at '$2' see --help"
            exit 0
        fi
    
        if [[ -n $3 ]]; then    
            if [[ $3 == '-i' ]]; then
                if [[ -n $4 || -n $5 ]]; then
                    IFACE0=$4; IFACE1=$5
                else
                    echo "Invalid interfaces at '$4' or '$5' see --help"
                    exit 0
                fi
            else
                echo "Invalid option '$3' see --help"
                exit 0
            fi
        fi
    fi    
fi

# Use error checking for exacution of external commands and report
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
    [[ $STEP_OK == 0 ]] && echo "$PASS   $1" || echo "$WARN FAILED  $1"
    return $STEP_OK
}

#######################################
# Building a sane working environment #
#######################################
depends()
{
    IPT="/sbin/iptables"
    if [[ -z $IFACE0 ]]; then IFACE0="eth0"; fi 
    if [[ -z $IFACE1 ]]; then IFACE1="wlan0"; fi
    AP="at0"
    MON="wlan0mon"
    VPN="tun0"
    VPNI="tap+"
    AP_GATEWAY=$(grep routers dhcpd.conf | awk -Frouters '{print $2}' | cut -d ';' -f 1 | cut -d ' ' -f 2)
    AP_SUBNET=$(grep netmask dhcpd.conf | awk -Fnetmask '{print $2}' | cut -d '{' -f 1 | cut -d ' ' -f 2 | cut -d ' ' -f 1)
    AP_IP=$(grep netmask dhcpd.conf | awk -Fnetmask '{print $1}' | cut -d ' ' -f 1)
    AP_BROADCAST=$(grep broadcast-address dhcpd.conf | awk -Fbroadcast-address '{print $2}' | cut -d ';' -f 1 | cut -d ' ' -f 2)
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
    QUES=${BLD_BLU}?${TXT_RST}       # Questions
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
    # Allow us to call new temrinals
    echo -ne "\n$INFO Granting X Access to everyone\n"
    action xhost +
    next
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
        if [[ -z $IFACE0 ]]; then IFACE0="eth0"; fi

        read -p "$QUES What is your default Wireless interface? [wlan0]: " WLAN
        if [[ -z $IFACE1 ]]; then IFACE1="wlan0"; fi

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
        if [[ -z $IFACE0 ]]; then IFACE0="eth0"; fi
        
        if [[ -z $IFACE1 ]]; then IFACE1="wlan0"; fi

        if [[ -e /etc/init.d/net.$IFACE1 ]]; then
            get_RCstatus "$IFACE1"
            if [[ $STATUS == 'started' ]]; then
                /etc/init.d/net.$IFACE1 stop
            fi
        fi
        get_state $IFACE1
        [[ $STATE != 'DOWN' ]] && ip link set $IFACE1 down
        iwconfig $IFACE1 mode managed # Force managed mode upon wlan because there is a glitch that can block airmon from bringing the interface up if not previously done
        ESSID="Pentoo"
        CHAN="1"
        BEACON="100"
        PPS="100"
    fi
}

keepalive()
{
    read -p "$WARN Press ctrl+c when you are ready to go down!" ALLINTHEFAMILY # Protect this script from going down hastily
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
    xhost -
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
        local DEVICE=$IFACE0 
    elif [[ $MENU_REBUILD_NETWORK == 2 ]]; then
        local DEVICE=$IFACE1    
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
    get_state "$IFACE1"
    while [[ $STATE != 'DOWN' ]]; do 
        ip link set "$IFACE1" down
    done

    echo -n "$INFO Airmon-zc comming up"
    airmon-zc check kill
    sleep 0.5
    airmon-zc start $IFACE1
    next

    if [[ $MENUCHOICE == 2 ]]; then
        echo -n "$INFO STARTING SERVICE: AIRBASE-NG" #-Z -a -0
        action airbase-ng -c $CHAN -x $PPS -I $BEACON -e $ESSID -P -v $MON > $sessionfolder/logs/airbase-ng.log &
        sleep 1.5 ## future put this and the next line in a more comprehensive loop
        next
    elif [[ $MENUCHOICE == 1 ]]; then # used elif instead of just else for more comprehensive structure so users may modify easier.
        echo -n "$INFO STARTING SERVICE: KARMA AIRBASE-NG"
        action airbase-ng $MON -c $CHAN -x $PPS -I $BEACON -e $ESSID -P -C 15 -v > $sessionfolder/logs/airbase-ng.log &
        sleep 1.5
        next
    fi

    echo -ne "\n$INFO Assigning IP and Route to $AP\n"
    get_state "$AP"
    while [[ $STATE == 'DOWN' || -z $(ip addr list | grep $AP) ]]; do #check AP state if down go up, if AP has not loaded yet wait a bit
        sleep 0.3
        ip link set $AP up
        get_state "$AP"
    done
    # setting ip and route doesn't always take, to ensure it sticks and check no other routes or ip's are getting assigned not by us then remove them if so.
    local CHK_IP=$(ip addr | grep $AP | grep -i inet | awk -Finet '{print $2}' | awk -F brd '{print $1}' | cut -d ' ' -f 2)
    if [[ -n $CHK_IP && $CHK_IP != "$AP_GATEWAY"/32 ]]; then
        action ip addr del $CHK_IP dev $AP; next
    fi

    local CHK_IP=$(ip route | grep $AP | awk -Fvia '{print $1}')
    if [[ -n $CHK_IP && $CHK_IP != "$AP_IP"/24  ]]; then
        action ip route flush $CHK_IP; next
    fi

    while [[ -z $(ip addr | grep $AP | grep -i inet | awk -Finet '{print $2}' | awk -F/ '{print $1}') ]]; do
        sleep 0.3
        action ip addr add $AP_GATEWAY broadcast $AP_BROADCAST dev $AP; next
    done

    while [[ -z $(route -n | grep $AP | grep $AP_GATEWAY ) ]]; do
        sleep 0.3
        action route add -net $AP_IP netmask $AP_SUBNET gw $AP_GATEWAY; next
    done
    route -n
    AIRBASE="On"
    xterm -hold -bg black -fg blue -T "N4P Victims" -geometry 65x15 -e ./monitor.sh $AP &>/dev/null &
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

    echo -ne "\n Building $BRIDGE now with $BRIDGE $RESP_BR_2 $BRIDGE_RESP_BR_1"
    if [[ -n $FAST_HOSTAPD ]]; then
        action iw dev $RESP_BR_2 set 4addr on; next
    fi

    get_state "$RESP_BR_2"
    while [[ $STATE == 'DOWN' || -z $(ip addr list | grep $RESP_BR_2) ]]; do 
        sleep 0.2
        ip link set $RESP_BR_2 up
        get_state "$RESP_BR_2"
    done

    get_state "$RESP_BR_1"
    while [[ $STATE == 'DOWN' || -z $(ip addr list | grep $RESP_BR_1) ]]; do 
        sleep 0.2
        ip link set $RESP_BR_1 up
        get_state "$RESP_BR_1"
    done
    sleep 2
    action brctl addbr $BRIDGE; next
    sleep 0.3
    action brctl addif $BRIDGE $RESP_BR_1; next
    sleep 0.3
    action brctl addif $BRIDGE $RESP_BR_2; next
    sleep 0.3
    ip link set $BRIDGE up
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

                echo -e "$INFO We need to setup the interfaces you are going to use with $BRIDGE \n e.g. $IFACE0 and $AP, here are your possible choices"
                echo "${BLD_ORA}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${TXT_RST}"
                ip addr
                echo "{BLD_ORA}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${TXT_RST}"

                read -p "$QUES Please tell me the first interface to use: " RESP_BR_1
                if [[ -z $RESP_BR_1 ]]; then RESP_BR_1=$IFACE0; fi
                
                read -p "$QUES Please tell me the second interface to use: " RESP_BR_2
                if [[ -z $RESP_BR_2 ]]; then # Run default check to verify what our default interface should be encase the user forgot to set this properly.
                    if [[ $AIRBASE == 'On' ]]; then
                        RESP_BR_2=$AP
                    else # For Hostapd
                       RESP_BR_2=$IFACE1 
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
    elif [[ $BRIDGED == 'True' ]]; then # If we are here then user set credentials at launch
        BRIDGE=br0
        RESP_BR_1=$IFACE0
        if [[ -n $FAST_AIRBASE ]]; then
            RESP_BR_2=$AP
        elif [[ -n $FAST_HOSTAPD ]]; then
           RESP_BR_2=$IFACE1
        fi
        openrc_bridge
    fi
}

dhcp()
{
    if [[ -n $(cat /etc/dhcp/dhcpd.conf | grep -i Pentesters_AP | awk '{print $2}') ]]; then
        if [[ $BRIDGED != 'True' ]]; then
            /etc/init.d/dhcpd restart # This speeds authentication up and enables logging from dhcpd logs
        else
            /etc/init.d/net.$BRIDGE start
        fi
    else # We apparently don't have the proper configuration file. Make the changes and action again
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
    echo -ne "$INFO Flushing old rules\n"
    /etc/init.d/iptables stop
    $IPT -F
    $IPT -t nat -F
    $IPT --delete-chain
    $IPT -t nat --delete-chain
    $IPT -F FORWARD
    $IPT -t filter --flush FORWARD
    $IPT -t filter --flush INPUT

    # Set default policies for all three default chains
    echo -ne "$INFO Setting default policies\n"
    $IPT -P OUTPUT ACCEPT

    echo -ne "$INFO We will allow ip forwarding\n"
    echo 1 > /proc/sys/net/ipv4/ip_forward
    $IPT -P FORWARD ACCEPT

    # Enable free use of loopback interfaces
    echo -ne "$INFO  Allowing loopback devices\n"
    $IPT -A INPUT -i lo -j ACCEPT
    $IPT -A OUTPUT -o lo -j ACCEPT

    ## permit local network
    echo -ne "$INFO  Permit local network\n"
    $IPT -A INPUT -i $IFACE0 -j ACCEPT
    $IPT -A OUTPUT -o $IFACE0 -j ACCEPT

    ## DHCP
    echo -ne "$INFO  Allowing DHCP server\n"
    $IPT -A INPUT -t nat -p udp --sport 67 --dport 68 -j ACCEPT

    ## Allow Samba
    echo -ne "$INFO Configuring Samba\n"
    $IPT -A INPUT -i $IFACE0 -p tcp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
    $IPT -A INPUT -i $IFACE0 -p udp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
    $IPT -A OUTPUT -o $IFACE0 -p tcp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
    $IPT -A OUTPUT -o $IFACE0 -p udp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT

    fw_pre_services
}

fw_services()
{
    ## Allow DNS Server
    echo -ne "$INFO Allowing dns on port 53\n"
    $IPT -A INPUT -t nat -p udp -m udp --dport 53 -j ACCEPT

    ## SSH (allows SSH through firewall, from anywhere on the WAN)
    echo -ne "$INFO Allowing ssh on port 22\n"
    $IPT -A INPUT -t nat -p tcp --dport 22 -j ACCEPT

    ## Web server
    echo -ne "$INFO Allowing http on port 80 and https on 443\n"
    $IPT -A INPUT -t nat -p tcp -m multiport --dports 80,443 -j ACCEPT
}

vpn_confirmed()
{
    #Allow TUN interface connections to OpenVPN server
    echo -ne "$INFO Allowing openVPN\n"
    $IPT -A INPUT -i $VPN -j ACCEPT
    #allow TUN interface connections to be forwarded through other interfaces
    $IPT -A FORWARD -i $VPN -j ACCEPT
    # Allow TAP interface connections to OpenVPN server
    $IPT -A INPUT -i $VPNI -j ACCEPT
    # Allow TAP interface connections to be forwarded through other interfaces
    $IPT -A FORWARD -i $VPNI -j ACCEPT
    # I've been called into action
    echo -ne "$INFO OpenRC now bringing up OpenVPN\n"
    /etc/init.d/openvpn start
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
    echo -ne "$INFO Drop everything else\n"
    $IPT -A INPUT -i $IFACE0 -j LOG
    $IPT -A INPUT -i $IFACE0 -j DROP
    #
    # Save settings
    #
    echo -ne "$INFO Saving settings and bringing iptables back online\n"
    /etc/init.d/iptables save
    echo ""
    /etc/init.d/iptables start
    
    ## list the iptables rules as confirmation
    echo -ne "$INFO Listing the iptables rules as confirmation\n"
    $IPT -L -v
}

fw_up()
{ 
    fw_redundant
    if [[ $BRIDGED != 'True' ]]; then
        echo -ne "$INFO Allowing wirless for airbase, routing $AP through $IFACE0 be sure airbase was configured for $AP and $IFACE0 as the output otherwise adjust these settings\n"
        $IPT -t nat -A POSTROUTING -o $IFACE0 -j MASQUERADE
        $IPT -A FORWARD -i $AP -o $IFACE0 -j ACCEPT
        $IPT -A FORWARD -i $IFACE0 -o $AP -j ACCEPT
        #$IPT -A FORWARD -i $IFACE1 -o $IFACE0 -j ACCEPT
        #$IPT -A FORWARD -i $IFACE0 -o $IFACE1 -j ACCEPT
    fi
    fw_closure
}

fw_down()
{ 
    fw_redundant
    echo -e "$INFO Defaults loaded for daily use.\n"
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
