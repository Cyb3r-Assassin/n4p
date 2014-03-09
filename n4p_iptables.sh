#!/bin/bash

if [[ $(whoami) != 'root'  ]]; then 
    echo "[$CRIT] Please Run This Script As Root or With Sudo!"
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
DIR_CONF=/etc/n4p
DIR_LOGO=/usr/share/n4p

get_name() # Retrieve the config values
{
    USE=$(grep $1 ${DIR_CONF}/n4p.conf | awk -F= '{print $2}')
}

IPT="/sbin/iptables"
AP="at0"
VPN="tun0"
VPNI="tap+"
sessionfolder=/tmp/n4p
get_name "IFACE0="; IFACE0=$USE
get_name "IFACE1="; IFACE1=$USE
get_name "AP="; UAP=$USE
get_name "BRIDGED="; BRIDGED=$USE
get_name "BRIDGE_NAME="; BRIDGE_NAME=$USE
get_name "ATTACK="; ATTACK=$USE
get_name "USE_VPN="; USE_VPN=$USE
# Text color variables
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

echo "$(cat ${DIR_LOGO}/firewall.logo)"; sleep 2.5

##################################################################
######################Build the firewall##########################
##################################################################
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


    if [[ $USE_VPN == True ]]; then
        # Allow TUN interface connections to OpenVPN server
        echo -ne "$INFO Allowing openVPN\n"
        $IPT -A INPUT -i $VPN -j ACCEPT
        # Allow TUN interface connections to be forwarded through other interfaces
        $IPT -A FORWARD -i $VPN -j ACCEPT
        # Allow TAP interface connections to OpenVPN server
        $IPT -A INPUT -i $VPNI -j ACCEPT
        # Allow TAP interface connections to be forwarded through other interfaces
        $IPT -A FORWARD -i $VPNI -j ACCEPT
        # I've been called into action
        echo -ne "$INFO OpenRC now bringing up OpenVPN\n"
        /etc/init.d/openvpn start
    fi

    ## Allow DNS Server
    echo -ne "$INFO Allowing dns on port 53\n"
    $IPT -A INPUT -t nat -p udp -m udp --dport 53 -j ACCEPT

    ## SSH (allows SSH through firewall, from anywhere on the WAN)
    echo -ne "$INFO Allowing ssh on port 22\n"
    $IPT -A INPUT -t nat -p tcp --dport 22 -j ACCEPT

    ## Web server
    echo -ne "$INFO Allowing http on port 80 and https on 443\n"
    $IPT -A INPUT -t nat -p tcp -m multiport --dports 80,443,8080 -j ACCEPT
}

fw_up()
{ 
    if [[ $BRIDGED == "False" ]]; then
        if [[ $UAP == "AIRBASE" ]]; then
            echo -ne "$INFO Allowing wirless for airbase, routing $AP through $IFACE0 be sure airbase was configured for $AP and $IFACE0 as the output otherwise adjust these settings\n"
            $IPT -t nat -A POSTROUTING --out-interface $IFACE0 -j MASQUERADE
            $IPT -A FORWARD -i $AP -o $IFACE0 -j ACCEPT
        elif [[ $UAP == "HOSTAPD" ]]; then
            echo -ne "$INFO Allowing wirless for hostapd, routing $AP through $IFACE0 be sure hostapd was configured for $AP and $IFACE0 as the output otherwise adjust these settings\n"
            $IPT -A FORWARD -i $IFACE1 -o $IFACE0 -j ACCEPT
            $IPT -A FORWARD -i $IFACE0 -o $IFACE1 -j ACCEPT
        else
            echo "[$WARN] ERROR in AP configuration file, no AP found"
        fi
    fi

    [[ $ATTACK == "SslStrip" ]] && $IPT -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 10000
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
    
    echo -ne "$INFO Listing the iptables rules as confirmation\n"
    time=12
    while [[ $time > 0 ]]; do
        $IPT -L -v
        echo "Window closing automatically in $time seconds."
        sleep 1
        time=$(($time-1))
    done
}

start()
{
    if [[ -n $(ps -A | grep -i airbase) ]]; then 
        fw_redundant
        fw_up
        fw_closure
    else
        fw_redundant
        echo "[$OK] Defaults loaded for daily use."
        fw_closure
    fi
}
start