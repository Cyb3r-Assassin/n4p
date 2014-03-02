#!/bin/bash
BLD_RED=${txtbld}$(tput setaf 1) # red
TXT_RST=$(tput sgr0)             # Reset
echo "" > /var/log/messages

while true; do
	while read line
	do gotchya=$(egrep 'DHCPACK|$1' | awk -Fon '{print $2'})
	done < /var/log/messages
	clear
	echo "${BLD_TEA}$(cat /usr/share/n4p/monitor.logo)${TXT_RST}"
	echo -e "$gotchya \n"
	sleep 8
done