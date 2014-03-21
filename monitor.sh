#!/bin/bash
BLD_RED=${txtbld}$(tput setaf 1) # red
TXT_RST=$(tput sgr0)             # Reset

DIR_LOGO=/usr/share/n4p
LOG_NEW=/var/log/everything/current
LOG_COMPATABILITY=/var/log/messages

if [[ -f $LOG_NEW ]]; then
    USE=$LOG_NEW
elif [[ -f $LOG_COMPATABILITY ]]; then
    USE=$LOG_COMPATABILITY
else
    echo "We were unable to locate any system log files\nPlease fix or use a different mode"
fi

mv $USE ${USE}.bak
echo "" > $USE

while true; do
        while read line
        do gotchya=$(egrep 'DHCPACK|$1' | awk -Fon '{print $2'})
        done < $USE
        clear
        echo "${BLD_TEA}$(cat ${DIR_LOGO}/monitor.logo)${TXT_RST}"
        echo -e "$gotchya \n"
        sleep 8
done

killemAll()
{
    rm $USE
    mv ${USE}.bak $USE
    exit 0
}

trap killemAll INT HUP;