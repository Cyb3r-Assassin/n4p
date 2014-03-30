#!/bin/bash

if [[ $(whoami) != 'root'  ]]; then 
    echo "[$CRIT] Please Run This Script from n4p!"
    exit 0
fi

#retrieve absolute path structures so we can use symlinks and config files
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do # resolve $SOURCE until the file is no longer a symlink
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="${DIR}/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it's relativeness to the path where the symlink file was located
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
BLD_PUR=${txtbld}$(tput setaf 5) # purple
BLD_TEA=${txtbld}$(tput setaf 6) # teal
TXT_RST=$(tput sgr0)             # Reset
WARN="${BLD_TEA}[${TXT_RST}${BLD_PUR} * ${TXT_RST}${BLD_TEA}]${TXT_RST}"

echo "$(cat ${DIR_LOGO}/firewall.logo)"; sleep 2.5

##################################################################
######################Build the firewall##########################
##################################################################
if [ -e /proc/sys/net/ipv4/tcp_ecn ]
then
        echo 0 > /proc/sys/net/ipv4/tcp_ecn
fi

fw_start()
{
    ## Flush rules
    echo -en "Flushing old rules\n"
    /etc/init.d/iptables stop
    $IPT -F
    $IPT -X

    # Set default policies for all three default chains
    echo -en "Setting default policies\n"
    $IPT -P INPUT DROP
    $IPT -P OUTPUT ACCEPT
    echo 1 > /proc/sys/net/ipv4/ip_forward
    $IPT -P FORWARD ACCEPT
    $IPT -N allowed-connection
    $IPT -A allowed-connection -i lo -j ACCEPT
    if [[ $USE_VPN == True ]]; then
        $IPT -A allowed-connection -i $VPN -j ACCEPT
        $IPT -A allowed-connection -i $VPNI -j ACCEPT
        $IPT -A allowed-connection -o $VPN -j ACCEPT
        $IPT -A allowed-connection -o $VPNI -j ACCEPT
        /etc/init.d/openvpn start
    fi

    $IPT -A allowed-connection -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    $IPT -A allowed-connection -m conntrack --ctstate INVALID -j DROP
    $IPT -A allowed-connection -m limit -j LOG --log-prefix "Bad packet from ${IFACE0}:"


    #Incoming traffic
    echo -en "Creating incoming ssh traffic chain\n"
    $IPT -N allow-ssh-traffic-in
    #Flood protection
    $IPT -A allow-ssh-traffic-in -m limit --limit 1/second -p tcp --dport 22 -j ACCEPT
    $IPT -A allow-ssh-traffic-in -m conntrack --ctstate NEW -p tcp --dport 22 -j ACCEPT

    echo -en "Creating dns traffic chain\n"
    $IPT -N allow-dns-traffic-in
    $IPT -A allow-dns-traffic-in -p udp -m udp --dport 53 -m conntrack --ctstate NEW,RELATED,ESTABLISHED -j ACCEPT

    echo -en "Creating incoming http/https traffic chain\n"
    $IPT -N allow-www-traffic-in
    $IPT -A allow-www-traffic-in -m limit --limit 1/second -p tcp -m multiport --dports 443 -j ACCEPT
    $IPT -A INPUT -p tcp -m multiport --dports 443 -m conntrack --ctstate NEW -j ACCEPT

    echo -en "Creating incoming DHCP server\n"
    $IPT -N allow-dhcp-traffic-in
    #Flood protection
    $IPT -A allow-dhcp-traffic-in -m limit --limit 1/second -p udp --sport 67 --dport 68 -j ACCEPT
    $IPT -A allow-dhcp-traffic-in -m conntrack --ctstate NEW,RELATED,ESTABLISHED -p udp --sport 67 --dport 68 -j ACCEPT

    echo -en "Creating incoming Torrent rules\n"
    $IPT -N allow-torrent-traffic-in
    $IPT -A allow-torrent-traffic-in -p udp -m multiport --dports 6881,8881 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
    $IPT -A allow-torrent-traffic-in -p tcp -m multiport --dports 6881,6999 -j ACCEPT


    echo -en "Creating incoming SAMBA rules\n"
    $IPT -N allow-samba-traffic-in
    $IPT -A allow-samba-traffic-in -p tcp -m multiport --dports 445,135,136,137,138,139 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
    $IPT -A allow-samba-traffic-in -p udp -m multiport --dports 445,135,136,137,138,139 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT


    if [[ $BRIDGED == "False" ]]; then
        if [[ $UAP == "AIRBASE" ]]; then
            echo -en "Allowing wirless for airbase, routing $AP through $IFACE0 be sure airbase was configured for $AP and $IFACE0 as the output otherwise adjust these settings\n"
            $IPT -A POSTROUTING -t nat --out-interface $IFACE0 -j MASQUERADE
            #Be generous with the AP
            $IPT -A allowed-connection -i $AP -j ACCEPT
            $IPT -A allowed-connection -i $AP -m limit -j LOG --log-prefix "Bad packet from ${AP}:"
            #Be strict with what we allow the AP to do
            #$IPT -A allowed-connection -p tcp -i $AP -m multiport --dports 80,443,53,68,67 -j ACCEPT
            #$IPT -A allowed-connection -p udp -i $AP -m multiport --dports 80,443,53,68,67 -j ACCEPT
            $IPT -A allowed-connection -i $AP -o $IFACE0 -j ACCEPT
        elif [[ $UAP == "HOSTAPD" ]]; then
            echo -ne "$INFO Allowing wirless for hostapd, routing $AP through $IFACE0 be sure hostapd was configured for $AP and $IFACE0 as the output otherwise adjust these settings\n"
            $IPT -A allowed-connection -i $IFACE1 -o $IFACE0 -j ACCEPT
            $IPT -A allowed-connection -i $IFACE0 -o $IFACE1 -j ACCEPT
        else
            echo -ne "[$WARN] ERROR in AP configuration file, no AP found\n"
        fi
    fi

    [[ $ATTACK == "SslStrip" ]] && $IPT  -t nat -A PREROUTING -i $AP -p tcp --destination-port 80 -j REDIRECT --to-ports 10000

    #ICMP traffic
    echo -en "Creating icmp chain\n"
    $IPT -A allowed-connection -p icmp --icmp-type echo-request -m recent --name ping_limiter --set
    $IPT -A allowed-connection -p icmp --icmp-type echo-request -m recent --name ping_limiter --update --hitcount 6 --seconds 4 -j DROP
    $IPT -A allowed-connection -p icmp --icmp-type echo-request -j ACCEPT
    #Trap Portscanners
    $IPT -I TCP -p tcp -m recent --update --seconds 60 --name TCP-PORTSCAN -j REJECT --reject-with tcp-rst
    $IPT -A allowed-connection -p tcp -m recent --set --name TCP-PORTSCAN -j REJECT --reject-with tcp-rst
    $IPT -I UDP -p udp -m recent --update --seconds 60 --name UDP-PORTSCAN -j REJECT --reject-with port-unreach
    $IPT -A allowed-connection -p udp -m recent --set --name UDP-PORTSCAN -j REJECT --reject-with icmp-port-unreach
    $IPT -A allowed-connection -p icmp -j LOG --log-prefix "Bad ICMP traffic:"

    # Apply and add invalid states to the chains
    echo -en "Applying chains to INPUT\n"
    $IPT -A INPUT -j allow-ssh-traffic-in
    $IPT -A INPUT -j allow-dhcp-traffic-in
    $IPT -A INPUT -j allow-samba-traffic-in
    $IPT -A INPUT -j allow-dns-traffic-in
    $IPT -A INPUT -j allow-torrent-traffic-in
    $IPT -A INPUT -j allow-www-traffic-in
    $IPT -A INPUT -j allowed-connection
    $IPT -A INPUT -j DROP
    $IPT -A INPUT -j REJECT --reject-with icmp-proto-unreachable


    for x in lo $IFACE0 $IFACE1 $AP $VPN $VPI
    do
        if [ -e /proc/sys/net/ipv4/conf/${x}/rp_filter ]; then
            echo 1 > /proc/sys/net/ipv4/conf/${x}/rp_filter
        fi
    done

    /etc/init.d/iptables save
    /etc/init.d/iptables start
}
fw_start