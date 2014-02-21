#!/bin/bash
if [[ $(id -u) == 0 ]]; then # Verify we are not root
	xhost +
	sudo ./n4p_main.sh $1 $2 $3 $4 $5
else
   echo "This script can not be ran as root or with sudo. If you are root then run n4p_main.sh directly" 1>&2
   exit 1
fi
exit 0
