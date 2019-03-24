#!/bin/bash

#######################################################
### Autor: Nico Hartung <nicohartung1@googlemail.com> #
#######################################################

# Skript sollte ab FritzOS 6.0 (2013) funktioneren - also auch für die 6.8x und 6.9x
# Dieses Bash-Skript nutzt das Protokoll TR-064 nicht die WEBCM-Schnittstelle

# http://fritz.box:49000/tr64desc.xml
# https://wiki.fhem.de/wiki/FRITZBOX#TR-064
# https://avm.de/service/schnittstellen/

# Thanks to Dragonfly (https://homematic-forum.de/forum/viewtopic.php?t=27994)


###=======###
# Variablen #
###=======###

IPS="fritz.box"

FRITZUSER=""
FRITZPW="passwort-weboberflaeche"

###====###
# Skript #
###====###

#location="/upnp/control/deviceconfig"
#uri="urn:dslforum-org:service:DeviceConfig:1"
#action='Reboot'

#location="/upnp/control/deviceinfo"
#uri="urn:dslforum-org:service:DeviceInfo:1"
#action='GetSecurityPort'
#SoapParam='NewPersistentData'
#SoapParamString="<$SoapParam>$1</$SoapParam>"

#location="/upnp/control/wanpppconn1"
#uri="urn:dslforum-org:service:WANPPPConnection:1"
#action='GetGenericPortMappingEntry'
#SoapParam='NewPortMappingIndex'
#SoapParamString="<$SoapParam>1</$SoapParam>"

#location="/upnp/control/wanpppconn1"
#uri="urn:dslforum-org:service:WANPPPConnection:1"
#action='DeletePortMapping'           # entweder   
#action='GetSpecificPortMappingEntry' # oder
#SoapParamString="<NewRemoteHost>0.0.0.0</NewRemoteHost>
#<NewExternalPort>80</NewExternalPort>
#<NewProtocol>TCP</NewProtocol>"


location="/upnp/control/wanpppconn1"
uri="urn:dslforum-org:service:WANPPPConnection:1"
action='AddPortMapping'
SoapParamString="<NewRemoteHost>0.0.0.0</NewRemoteHost>
<NewExternalPort>80</NewExternalPort>
<NewProtocol>TCP</NewProtocol>
<NewInternalPort>80</NewInternalPort>
<NewInternalClient>192.168.0.213</NewInternalClient>
<NewEnabled>1</NewEnabled>
<NewPortMappingDescription>HTTP-Server</NewPortMappingDescription>
<NewLeaseDuration>0</NewLeaseDuration>"

for IP in ${IPS}; do
        curl -k -m 5 --anyauth -u "$FRITZUSER:$FRITZPW" https://$IP:49443$location -H 'Content-Type: text/xml; charset="utf-8"' -H "SoapAction:$uri#$action" -d "<?xml version='1.0' encoding='utf-8'?><s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'><s:Body><u:$action xmlns:u='$uri'>$SoapParamString</u:$action></s:Body></s:Envelope>" -s
#       curl -k -m 5 --anyauth -u "$FRITZUSER:$FRITZPW" https://$IP:49443$location -H 'Content-Type: text/xml; charset="utf-8"' -H "SoapAction:$uri#$action" -d "<?xml version='1.0' encoding='utf-8'?><s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'><s:Body><u:$action xmlns:u='$uri'></u:$action></s:Body></s:Envelope>" -s
done
