#!/bin/bash
echo "" > /var/log/messages
while true; do
	while read line
	do gotchya=$(egrep 'DHCPACK|$1' | awk -Fon '{print $2'})
	done < /var/log/messages
	echo -e "$gotchya \n"
	sleep 8
done