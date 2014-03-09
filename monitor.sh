#!/bin/bash
BLD_RED=${txtbld}$(tput setaf 1) # red
TXT_RST=$(tput sgr0)             # Reset
mv /var/log/messages /var/log/messages.bak
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

killemAll()
{
    mv /var/log/messages.bak /var/log/messages
    exit 0
}

trap killemAll INT HUP;