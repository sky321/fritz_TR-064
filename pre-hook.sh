#!/bin/sh

echo "open port 80 ...."

IPS=$( grep IPS /root/.fritz.cnf | sed 's|IPS=||' )

FRITZUSER=$( grep FRITZUSER /root/.fritz.cnf | sed 's|FRITZUSER=||' )
FRITZPW=$( grep FRITZPW /root/.fritz.cnf | sed 's|FRITZPW=||'  | base64 -d )

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
done
