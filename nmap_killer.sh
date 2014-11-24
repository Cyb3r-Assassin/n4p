#/bin/bash
if [[ $(id -u) != 0 ]]; then # Verify we are root if not exit
   echo "Please Run This Script As Root or With Sudo!" 1>&2
   exit 1
fi

if [[ $1 == file ]]; then
  while read line 
  do
    ip=$line
    file=${ip:0:-3}
    mkdir $file
    nmap -sP $ip | grep -i report | awk -F"for" '{ print $2 }' | cut -d' ' -f2 > $file/$file
    while read line
    do
      nmap -sV -T4 -O -F --version-light $line > $file/$line
      #nmap -A $line > $file/$line
    done < $file/$file
  done < ips
else
  ip=$1
  file=${ip:0:-3}
  mkdir $file
  nmap -sP $ip | grep -i report | awk -F"for" '{ print $2 }' | cut -d' ' -f2 > $file/$file
  while read line
  do
    nmap -sV -T4 -O -F --version-light $line > $file/$line
  done < $file/$file
fi