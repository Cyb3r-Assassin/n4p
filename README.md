##N4P for Pentoo and Gentoo Linux.
####Offensives network security application

* Configures network variables automatically for Airbase-ng with bridging and ipv4_forwarding ability.
* Configures all necessary elements and performs MITM, ARP, WPA Cracking, Sniffing and SSLstrip attacks.

Opening screenshot of n4p
![n4p](http://i.imgur.com/RGdtLR8.png)

Configuration file modified by user. All Access Point options, devices, and attacking methods are set here.
The user may modify options before launching new attacks without interrupting current attack, as long as the current attack window remains open.

> You may not comment out option lines but you may disable options if you decide on storing multiple possible options for testing.
> This is done by e.g. #IFACE1\=

Flexibility of ettercaps options have been preserved by allowing the user to change the options passed during execution.

> Ettercap default switches are -Tq the user could simply change that value to -Tqz if they wanted to disable initial arp.

![n4p.conf](http://i.imgur.com/gZ0aV5H.png)

N4P uses it's own DHCP configuration for it's Access Point creation. We do this so that connected targets can not view our machine inside the local network.
The only current limitation is n4p writes these settings into the system /etc/dhcp/dhcpd.conf file upon the first initial run time.
You are welcome to modify the ip range of this file but you must do it before you ever use n4p or manually remove the entry from /etc/dhcp/dhcpd.conf

![dhcp](http://i.imgur.com/xRtUt3y.png)

View of Access Point Airbase-ng running along with the custom connected clients monitor window. As clients connect to our AP their ip address will display here.
Other monitor options are available by changing the MONITOR_MODE= option in n4p.conf file from option 2

![AP](http://i.imgur.com/ORe3sma.png)

Option 1 shot performing a recon scan. This changes into a Handshake WPA2 Attack by setting the values in n4p.conf and running option 3

![recon](http://i.imgur.com/jwHZMOK.png)

After launching option 5 we view a snapshop of ettercap sniffing passwords off our rouge AP

![ettercap](http://i.imgur.com/AAqPNwE.png)

n4p stores all of our logs and reconnaissance data inside a tmp folder /tmp/n4p/
This folder is used by n4p internal attack communications. Such as capturing .cap files and cracking them with option 4
n4p will not destroy this folder so that the user may go back and store the files elsewhere for later analysis or for incorporating into pentesting reports.

![temp](http://i.imgur.com/t4JZKRP.png)

> The option to build the firewall must be ran last and each time you change attacks.

Some further options are available such as launching sslstrip against our victims by selecting option 8. And arpspoof has also been provided
allowing users to sniff networks without using a rouge AP. For this option you just set IFACE1= in the n4p.conf to the 
network device attached to the network and ARP_VICTIM to IP or Gateway you are attacking.

**Known Limitations**
Currently only 1 AP can be created at this time, but multiple monitoring interfaces may be created.
HOSTAPD has not been released back into n4p yet.

**BUGS**
Report all bugs to Cyb3r-Assassin directly through git contacts or irc.freenode