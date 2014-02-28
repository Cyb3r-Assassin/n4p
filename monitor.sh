#!/bin/bash
#retrieve absolute path structures so we can use symlinks and config files
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do # resolve $SOURCE until the file is no longer a symlink
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it's relativeness to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
BLD_RED=${txtbld}$(tput setaf 1) # red
TXT_RST=$(tput sgr0)             # Reset
echo "" > /var/log/messages

while true; do
	while read line
	do gotchya=$(egrep 'DHCPACK|$1' | awk -Fon '{print $2'})
	done < /var/log/messages
	clear
	echo "${BLD_TEA}$(cat $DIR/monitor.logo)${TXT_RST}"
	echo -e "$gotchya \n"
	sleep 8
done