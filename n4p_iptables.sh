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
    einfo "$INFO Flushing old rules\n"
    /etc/init.d/iptables stop
    $IPT -F
    $IPT -t nat -F
    $IPT -X
    $IPT -t nat -X
    $IPT -t mangle -X
    $IPT -F FORWARD
    $IPT -t filter --flush FORWARD
    $IPT -t filter --flush INPUT

    # Set default policies for all three default chains
    einfo "$INFO Setting default policies\n"
    $IPT -P INPUT DROP
    $IPT -P OUTPUT ACCEPT
    echo 1 > /proc/sys/net/ipv4/ip_forward
    $IPT -P FORWARD ACCEPT
    $IPT -N allowed-connection
    $IPT -F allowed-connection
    $IPT -A allowed-connection -i lo -j ACCEPT
    $IPT -A allowed-connection -o lo -j ACCEPT
    if [[ $USE_VPN == True ]]; then
        $IPT -A allowed-connection -i $VPN -j ACCEPT
        $IPT -A allowed-connection -i $VPNI -j ACCEPT
        $IPT -A allowed-connection -o $VPN -j ACCEPT
        $IPT -A allowed-connection -o $VPNI -j ACCEPT
        /etc/init.d/openvpn start
    fi
    $IPT -A allowed-connection -i $IFACE0 -m state --state NEW -j DROP
    $IPT -A allowed-connection -i $IFACE0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    $IPT -A allowed-connection -i $IFACE0 -m limit -j LOG --log-prefix "Bad packet from ${IFACE0}:"
    $IPT -A allowed-connection -j DROP
    
    #ICMP traffic
    einfo "Creating icmp chain"
    $IPT -N icmp_allowed
    $IPT -F icmp_allowed
    $IPT -A icmp_allowed -m state --state NEW -p icmp --icmp-type time-exceeded -j ACCEPT
    $IPT -A icmp_allowed -m state --state NEW -p icmp --icmp-type destination-unreachable -j ACCEPT
    $IPT -A icmp_allowed -p icmp -j LOG --log-prefix "Bad ICMP traffic:"
    $IPT -A icmp_allowed -p icmp -j DROP
  
    #Incoming traffic
    einfo "Creating incoming ssh traffic chain"
    $IPT -N allow-ssh-traffic-in
    $IPT -F allow-ssh-traffic-in
    #Flood protection
    $IPT -A allow-ssh-traffic-in -m limit --limit 1/second -p tcp --tcp-flags ALL RST --dport 22 -j ACCEPT
    $IPT -A allow-ssh-traffic-in -m limit --limit 1/second -p tcp --tcp-flags ALL FIN --dport 22 -j ACCEPT
    $IPT -A allow-ssh-traffic-in -m limit --limit 1/second -p tcp --tcp-flags ALL SYN --dport 22 -j ACCEPT
    $IPT -A allow-ssh-traffic-in -m state --state RELATED,ESTABLISHED -p tcp --dport 22 -j ACCEPT
    #outgoing traffic
    einfo "Creating outgoing ssh traffic chain"
    $IPT -N allow-ssh-traffic-out
    $IPT -F allow-ssh-traffic-out
    $IPT -A allow-ssh-traffic-out -p tcp --dport 22 -j ACCEPT
  
    einfo "Creating outgoing dns traffic chain"
    $IPT -N allow-dns-traffic-out
    $IPT -F allow-dns-traffic-out
    $IPT -A allow-dns-traffic-out -p udp -m udp --dport 53 -m conntrack --ctstate --state NEW -j ACCEPT
    
    einfo "Creating incoming http/https traffic chain"
    $IPT -N allow-www-traffic-in
    $IPT -F allow-www-traffic-in
    #Flood protection
    $IPT -A allow-www-traffic-in -m limit --limit 1/second -p tcp --tcp-flags ALL RST -m multiport --dports 80,443 -j ACCEPT
    $IPT -A allow-www-traffic-in -m limit --limit 1/second -p tcp --tcp-flags ALL FIN -m multiport --dports 80,443 -j ACCEPT
    $IPT -A allow-www-traffic-in -m limit --limit 1/second -p tcp --tcp-flags ALL SYN -m multiport --dports 80,443 -j ACCEPT
    $IPT -A allow-www-traffic-in -m state --state RELATED,ESTABLISHED -p tcp -m multiport --dports 80,443 -j ACCEPT

    einfo "Creating outgoing http/https traffic chain"
    $IPT -N allow-www-traffic-out
    $IPT -F allow-www-traffic-out
    $IPT -A allow-www-traffic-out -p tcp -m multiport --dports 80,443 -j ACCEPT
       
    einfo "Creating incoming DHCP server"
    $IPT -N allow-dhcp-traffic-in
    $IPT -F allow-dhcp-traffic-in
    #Flood protection
    $IPT -A allow-dhcp-traffic-in -m limit --limit 1/second -p udp --tcp-flags ALL RST --sport 67 --dport 68 -j ACCEPT
    $IPT -A allow-dhcp-traffic-in -m limit --limit 1/second -p udp --tcp-flags ALL FIN --sport 67 --dport 68 -j ACCEPT
    $IPT -A allow-dhcp-traffic-in -m limit --limit 1/second -p udp --tcp-flags ALL SYN --sport 67 --dport 68 -j ACCEPT
    $IPT -A allow-dhcp-traffic-in -m state --state RELATED,ESTABLISHED -p udp --sport 67 --dport 68 -j ACCEPT

    einfo "Creating outgoing DHCP server"
    $IPT -N allow-dhcp-traffic-out
    $IPT -F allow-dhcp-traffic-out
    $IPT -A allow-dhcp-traffic-out -p udp --sport 67 --dport 68 -j ACCEPT
    
    einfo "Creating incoming Torrent rules"
    $IPT -N allow-torrent-traffic-in
    $IPT -F allow-torrent-traffic-in
    #Flood protection
    $IPT -A INPUT -p udp -m multiport --dports 6881,8881 -m conntrack --ctstate --state NEW -j ACCEPT 
    $IPT -A INPUT -p tcp -m --port 6881:6999 -j ACCEPT 
    
    einfo "Creating outgoing Torrent traffic chain"
    $IPT -N allow-torrent-traffic-out
    $IPT -F allow-torrent-traffic-out
    $IPT -A allow-torrent-traffic-out -p udp -m multiport --dports 6881,8881 -j ACCEPT
    $IPT -A allow-torrent-traffic-out -p tcp -m --port 6881:6999 -j ACCEPT
    
    einfo "Creating incoming SAMBA rules"
    $IPT -N allow-samba-traffic-in
    $IPT -F allow-samba-traffic-in
    $IPT -A INPUT -i $IFACE0 -p tcp -m multiport --dports 445,135,136,137,138,139 -m conntrack --ctstate --state NEW -j ACCEPT
    $IPT -A INPUT -i $IFACE0 -p udp -m multiport --dports 445,135,136,137,138,139 -m conntrack --ctstate --state NEW -j ACCEPT
    
    einfo "Creating outgoing SAMBAt traffic chain"
    $IPT -N allow-samba-traffic-out
    $IPT -F allow-samba-traffic-out
    $IPT -A allow-samba-traffic-out -p udp -m multiport --dports 445,135,136,137,138,139 -j ACCEPT
    $IPT -A allow-samba-traffic-out -p tcp -m --dports 445,135,136,137,138,139 -j ACCEPT
    
    if [[ $BRIDGED == "False" ]]; then
        if [[ $UAP == "AIRBASE" ]]; then
            einfo "$INFO Allowing wirless for airbase, routing $AP through $IFACE0 be sure airbase was configured for $AP and $IFACE0 as the output otherwise adjust these settings\n"
            $IPT -N allow-ap-traffic
            $IPT -F allow-ap-traffic
            $IPT -A allow-ap-traffic -t nat -A POSTROUTING --out-interface $IFACE0 -j MASQUERADE
            eend $?
            #Be generous with the AP
            $IPT -A allow-ap-traffic -i $AP -m state --state NEW -j DROP
            $IPT -A allow-ap-traffic -i $AP -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
            $IPT -A allow-ap-traffic -i $AP -m limit -j LOG --log-prefix "Bad packet from ${AP}:"
            $IPT -A allow-ap-traffic -j DROP
            #Be strict with what we allow the AP to do
            #$IPT -I allow-ap-traffic -i $AP -j DROP 
            #$IPT -A allow-ap-traffic -p tcp -i $AP -m multiport --dports 80,443,53,68,67 -j ACCEPT
            #$IPT -A allow-ap-traffic -p udp -i $AP -m multiport --dports 80,443,53,68,67 -j ACCEPT
            #$IPT -A allow-ap-traffic -i $AP -o $IFACE0 -j ACCEPT
        elif [[ $UAP == "HOSTAPD" ]]; then
            echo -ne "$INFO Allowing wirless for hostapd, routing $AP through $IFACE0 be sure hostapd was configured for $AP and $IFACE0 as the output otherwise adjust these settings\n"
            $IPT -A allow-ap-traffic -i $IFACE1 -o $IFACE0 -j ACCEPT
            $IPT -A allow-ap-traffic -i $IFACE0 -o $IFACE1 -j ACCEPT
        else
            echo "[$WARN] ERROR in AP configuration file, no AP found"
        fi
    fi

    [[ $ATTACK == "SslStrip" ]] && $IPT -N allow-sslstrip-traffic; $IPT -F allow-sslstrip-traffic; $IPT -t nat -A allow-sslstrip-traffic -p tcp --destination-port 80 -j REDIRECT --to-port 10000
    
    #Catch portscanners
    einfo "Creating portscan detection chain"
    $IPT -N check-flags
    $IPT -F check-flags
    $IPT -A check-flags -p tcp --tcp-flags ALL FIN,URG,PSH -m limit --limit 5/minute -j LOG --log-level alert --log-prefix "NMAP-XMAS:"
    $IPT -A check-flags -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP
    $IPT -A check-flags -p tcp --tcp-flags ALL ALL -m limit --limit 5/minute -j LOG --log-level 1 --log-prefix "XMAS:"
    $IPT -A check-flags -p tcp --tcp-flags ALL ALL -j DROP
    $IPT -A check-flags -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -m limit --limit 5/minute -j LOG --log-level 1 --log-prefix "XMAS-PSH:"
    $IPT -A check-flags -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP
    $IPT -A check-flags -p tcp --tcp-flags ALL NONE -m limit --limit 5/minute -j LOG --log-level 1 --log-prefix "NULL_SCAN:"
    $IPT -A check-flags -p tcp --tcp-flags ALL NONE -j DROP
    $IPT -A check-flags -p tcp --tcp-flags SYN,RST SYN,RST -m limit --limit 5/minute -j LOG --log-level 5 --log-prefix "SYN/RST:"
    $IPT -A check-flags -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
    $IPT -A check-flags -p tcp --tcp-flags SYN,FIN SYN,FIN -m limit --limit 5/minute -j LOG --log-level 5 --log-prefix "SYN/FIN:"
    $IPT -A check-flags -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP

    # Apply and add invalid states to the chains
    einfo "Applying chains to INPUT"
    $IPT -A INPUT -m state --state INVALID -j DROP
    $IPT -A INPUT -p icmp -j icmp_allowed
    $IPT -A INPUT -j check-flags
    $IPT -A INPUT -i lo -j ACCEPT
    $IPT -A INPUT -j allow-ssh-traffic-in
    $IPT -A INPUT -j allowed-connection
  
    # Apply and add invalid states to the chains
    einfo "Applying chains to INPUT"
    $IPTABLES -A INPUT -m state --state INVALID -j DROP
    $IPTABLES -A INPUT -p icmp -j icmp_allowed
    $IPTABLES -A INPUT -j check-flags
    $IPTABLES -A INPUT -i lo -j ACCEPT
    $IPTABLES -A INPUT -j allow-ssh-traffic-in
    $IPTABLES -A INPUT -j allowed-connection

    einfo "Applying chains to FORWARD"
    $IPTABLES -A FORWARD -m state --state INVALID -j DROP
    $IPTABLES -A FORWARD -p icmp -j icmp_allowed
    $IPTABLES -A FORWARD -j check-flags
    $IPTABLES -A FORWARD -o lo -j ACCEPT
    $IPTABLES -A FORWARD -j allow-ssh-traffic-in
    $IPTABLES -A FORWARD -j allow-www-traffic-out
    $IPTABLES -A FORWARD -j allowed-connection

    einfo "Applying chains to OUTPUT"
    $IPTABLES -A OUTPUT -m state --state INVALID -j DROP
    $IPTABLES -A OUTPUT -p icmp -j icmp_allowed
    $IPTABLES -A OUTPUT -j check-flags
    $IPTABLES -A OUTPUT -o lo -j ACCEPT
    $IPTABLES -A OUTPUT -j allow-ssh-traffic-out
    $IPTABLES -A OUTPUT -j allow-dns-traffic-out
    $IPTABLES -A OUTPUT -j allow-www-traffic-out
    $IPTABLES -A OUTPUT -j allowed-connection
      
    /etc/init.d/iptables save
    /etc/init.d/iptables start