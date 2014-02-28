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
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it's relativeness to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

IFACE1=$1
JOB=$2
MON="wlan0mon"
# Text color variables
TXT_BLD=$(tput bold)             # Bold
BLD_PUR=${txtbld}$(tput setaf 5) # purple
BLD_TEA=${txtbld}$(tput setaf 6) # teal
BLD_RED=${txtbld}$(tput setaf 1) # red
TXT_RST=$(tput sgr0)             # Reset
WARN="${BLD_TEA}[${TXT_RST}${BLD_PUR} * ${TXT_RST}${BLD_TEA}]${TXT_RST}"

echo "${BLD_TEA}$(cat $DIR/recon.logo)${TXT_RST}"; sleep 2.5

get_name()
{
    USE=$(grep $1 $DIR/n4p.conf | awk -F= '{print $2}')
}

get_name "VICTIM_BSSID="; VICTIM_BSSID=$USE
get_name "CHAN="; CHAN=$USE

sessionfolder=/tmp/n4p # Set our tmp working configuration directory and then build config files
    if [ ! -d "$sessionfolder" ]; then mkdir "$sessionfolder"; fi
    	
if [[ -n $(ip addr | grep -i "$MON") ]]; then echo "$WARN Leftover scoobie snacks found! nom nom"; airmon-zc stop $MON; fi

get_state() # Retrieve the state of interfaces
{
    STATE=$(ip addr list | grep -i $1 | grep -i DOWN | awk -Fstate '{print $2}' | cut -d ' ' -f 2)
}

doit()
{
	get_state "$IFACE1"

	while [[ $STATE != 'DOWN' ]]; do 
		ip link set "$IFACE1" down
	done
	echo -n "$INFO Airmon-zc comming up"
	airmon-zc check kill
	sleep 0.5
	airmon-zc start $IFACE1
	sleep 1
    if [[ $JOB == "recon" ]]; then
	    xterm -hold -bg black -fg blue -T "Recon" -geometry 90x20 -e airodump-ng $MON &>/dev/null &
	else
	    xterm -hold -bg black -fg blue -T "Recon" -geometry 90x20 -e airodump-ng --bssid $VICTIM_BSSID -c $CHAN -w $sessionfolder/$VICTIM_BSSID.pcap $MON &>/dev/null &
    fi
}

keepalive()
{
    read -p "$WARN ${BLD_RED}Press ctrl^c when you are ready to go down!${TXT_RST}" ALLINTHEFAMILY # Protect this script from going down hastily
    if [[ $ALLINTHEFAMILY != 'SGFjayBUaGUgUGxhbmV0IQ==' ]]; then clear; keepalive; fi
}

killAll()
{
	airmon-zc stop $MON
	exit 0
}
trap killAll INT HUP;
doit
keepalive