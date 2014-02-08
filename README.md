# Networking 4 Pentesters #

Configures network variables automatically for Airbase-ng with bridging and ipv4_forwarding ability.

Configures all necessary iptables rules and prepares the system for MITM, ARP, and SSLstriping attacks.'

Copyright (C) 2014  [@Cyb3r-Assassin](https://github.com/Cyb3r-Assassin)

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
## Requirements ##
* Gentoo or Pentoo
* Airbase-ng


## Features
* Bridging
* IPv4 Forwarding
* MITM
* ARP
* SSLstripin Attack Mitigation

## Contact
* Twitter [@Cyb3r_Assassin](https://www.twitter.com/@Cyb3r_Assassin)
* **IRC** freenode.net Nick: Cyb3r-Assassin
* Gmail [Cyb3r-Assassin@cyberpunk.me](mailto:Cyb3r-Assassin@cyberpunk.me)
* Github [@Cyb3r-Assassin](https://github.com/Cyb3r-Assassin)

### Changlog
#### 0.5
Fixed firewall routing with bridging

Cleaned up loosely defined variables and variable structures

Updated find attributes to -wholename

Cleaned up error checking and improved error loops and added per process monitoring

Cleaned verbose outputs for easier follow along reading

Added -- switches/flags feature. e.g. n4p --help

Lot of code changes and additions. 
New methods of operations and package controll.

New less redundant more sane kill script logic

Removed dnsmasq - Was just too much for me to maintain and account for everyones boxes.

Changed ESSID to Pentoo

Changed some ip lease ranges on DHCPD

Added protection to prevent rfkill traps

More comprehensive text color usage.

added n4p_iptables.sh so iptables can be utilized without running n4p

Removed Hostapd. Was too hard for me to provide in production environment. Hostapd requires many config file 
attributes that are designed to be permanent on your box. If you want to use hostapd and not airbase then you're on your own.

#### 0.4 12-09-2013
Added path detection and absolute path relativeness for symlinking ability within ebuilds.

Moved dnsmasq settings into config file

#### 0.3 11-10-2013

Moved airmon-ng to Zero_Chaos's airmon-zc

Removed minor redundant variables

Encoded ESSID to fuck with ios6 because we can

#### 0.2 11-02-2013
iptable rules updated for sslstrip

#### 0.1 10-25-2013
Alpha testing
