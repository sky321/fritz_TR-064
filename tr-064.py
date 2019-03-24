#!/usr/bin/python
# -*- coding: iso-8859-1 -*-import os

import requests, sys, re
from requests.auth import HTTPDigestAuth
import xml.etree.ElementTree as ElementTree

DEBUG = 0

para = {
    'sservice'   : None,
    'controlURL' : None,
    'saction'    : None,
    'sparameter' : '',   # leer, wenn keine IN- Parameter benoetigt werden
    'outtag'     : None,
    'ret_text'   : None,
    'user'       : 'dslf-config',
    'password'   : 'xxxxxxx'
}

host  = "http://fritz.box:49000/"
shost = "https://fritz.box:49443/"

try:
    prog = sys.argv[1]
except:
    print 'TR-049.py [1..n] [0|1] erwartet.'
    sys.exit()
try:
    arg = sys.argv[2]
except:
    arg = '0'
  
def build_soap (saction, sservice, sparam):
    req = u"""<?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body> 
        <u:{action} xmlns:u={service}>
        {parameter}
        </u:{action}>
        </s:Body>
        </s:Envelope>""".format(action=saction, service='\"'+sservice+'\"', parameter=sparam)
    return  req.encode('utf-8')
   
def post_soap(host, para):
    headers = {"Content-Type":'text/xml; charset="utf-8"',
               "SOAPAction": para['sservice']+'#'+para['saction']}
    response = requests.post(
                url     = host + para['controlURL'],
                headers = headers,
                data    = build_soap(para['saction'], para['sservice'], para['sparameter']),
                auth    = HTTPDigestAuth(para['user'], para['password']),
                verify  = False) 
    if DEBUG: 
        print '\n1: Response Status=', response
        print '\n2: sservice=', para['sservice']
        print '\n3: saction:', para['saction']
        print '\n4: soap=', build_soap(para['saction'], para['sservice'], para['sparameter'])
    if not response.ok:
        return (False)   
    return response
 
# Ergebnis der SOAP- Aktion aufbereiten 
def response_to_xml_dict(host, tag, para, out=True):
    response = post_soap(host, para)
    try:
        if not response.ok:
            print 'HTTP-Fehler:', response
            sys.exit(1)
    except:
        print 'Fehler: kein gueltiger Rueckgabewert!'
        sys.exit(1)   
    # bei out=False wird keine Ergebnisausgabe von der Aktion erwartet
    if not out: return response.ok  
    if DEBUG: print '\n5: Response=', response.content    
    # Escapes und Namespaces umwandel/ausfiltern 
    response = response.content.replace("&lt;", "<").replace("&gt;", ">")
    response = response.replace("<s:", "<").replace("</s:", "</")
    response = response.replace("<u:", "<").replace("</u:", "</") 
    xml = '<?xml version="1.0" ?>'
    # Ergebnisblock ausfiltern. Das Ergebnis wird im Element 'tag' erwartet - immer 'Body' ausser bei Listen
    xml += response[response.find('<'+tag+'>'):response.find('</'+tag+'>')+len(tag)+3]
    if DEBUG: print '\n6: XML=', xml    
    tree = ElementTree.ElementTree(ElementTree.fromstring(xml)) 
    tag_dict = tree.getroot() 
    return tag_dict
   
   
# ************************ main ********************************
# Security Port ermitteln - Standardport = 49443
if prog == '1':
    para['saction']    = "GetSecurityPort"
    para['sservice']   = "urn:dslforum-org:service:DeviceInfo:1"
    para['controlURL'] = "upnp/control/deviceinfo"
    para['out_text']   = "SSL port:" 
    para['outtag']     = "NewSecurityPort"
    print para['out_text'], response_to_xml_dict(host, 'Body', para)[0].find(para['outtag']).text

# externe IP- Adresse abfragen     
elif prog == '2':
    para['saction']    = "GetExternalIPAddress"
    para['sservice']   = "urn:dslforum-org:service:WANPPPConnection:1"
    para['controlURL'] = "upnp/control/wanpppconn1"
    para['ret_text']   = "External IP Address:"
    para['outtag']     = "NewExternalIPAddress"
    print para['ret_text'], response_to_xml_dict(shost, 'Body', para)[0].find(para['outtag']).text
    
# GetPortMappingNumberOfEntries abfragen     
elif prog == '3':
    para['saction']    = "GetPortMappingNumberOfEntries"
    para['sservice']   = "urn:dslforum-org:service:WANPPPConnection:1"
    para['controlURL'] = "upnp/control/wanpppconn1"
    para['ret_text']   = "Portmapping number of entries:"
    para['outtag']     = "NewPortMappingNumberOfEntries"
    print para['ret_text'], response_to_xml_dict(shost, 'Body', para)[0].find(para['outtag']).text
    
# GetGenericPortMappingEntry abfragen     
elif prog == '4':
    para['saction']    = "GetGenericPortMappingEntry"
    para['sservice']   = "urn:dslforum-org:service:WANPPPConnection:1"
    para['controlURL'] = "upnp/control/wanpppconn1"
    para['sparameter'] = """<NewPortMappingIndex>0</NewPortMappingIndex>"""
    para['ret_text']   = "Portmapping entries[0]:"    
    print para['ret_text']
    for e in response_to_xml_dict(shost, 'Body', para)[0]:
        print "%s = %s" % (e.tag, e.text)

# Portmapping enable/disable    
elif prog == '5':
    para['saction']    = "AddPortMapping"
    para['sservice']   = "urn:dslforum-org:service:WANPPPConnection:1"
    para['controlURL'] = "upnp/control/wanpppconn1"
    para['sparameter'] = """<NewRemoteHost>0.0.0.0</NewRemoteHost>
        <NewExternalPort>80</NewExternalPort>
        <NewProtocol>TCP</NewProtocol>
        <NewInternalPort>80</NewInternalPort>
        <NewInternalClient>192.168.01.100</NewInternalClient>
        <NewPortMappingDescription>HTTP-Server</NewPortMappingDescription>
        <NewLeaseDuration>0</NewLeaseDuration>
        <NewEnabled>""" + arg + """</NewEnabled> """
    para['ret_text']   = 'Portmapping:'
    r = response_to_xml_dict(shost, '', para, False)   
    print para['ret_text'], ('Enable' if arg == '1' else 'Disable'), ('ok' if r else 'Fehler')

# Anzahl der konfigurierten Rufumleitungen anzeigen        
elif prog == '6':
    para['saction']    = "GetNumberOfDeflections"
    para['sservice']   = "urn:dslforum-org:service:X_AVM-DE_OnTel:1"
    para['controlURL'] = "upnp/control/x_contact"
    para['ret_text']   = "Anzahl Rufumleitungen:"
    para['outtag']     = "NewNumberOfDeflections"
    print para['ret_text'],  response_to_xml_dict(shost, 'Body', para)[0].find(para['outtag']).text

# Liste der Rufumleitungen anzeigen    
elif prog == '7':
    para['saction']    = "GetDeflections"
    para['sservice']   = "urn:dslforum-org:service:X_AVM-DE_OnTel:1"
    para['controlURL'] = "upnp/control/x_contact"
    para['ret_text']   = "Anzahl Rufumleitungen:"
    for item in response_to_xml_dict(shost, 'List', para).getchildren(): 
        for e in item:
            print "%s = %s" % (e.tag, e.text)
   
# Rufumleitung aktivieren/deaktivieren   
elif prog == '8':
    para['saction']    = "SetDeflectionEnable"
    para['sservice']   = "urn:dslforum-org:service:X_AVM-DE_OnTel:1"   
    para['controlURL'] = "upnp/control/x_contact"
    para['sparameter'] = """<NewDeflectionId>0</NewDeflectionId>
        <NewEnable>""" + arg + """</NewEnable>"""
    para['ret_text']   = "SetDeflectionEnable[0]:"
    r = response_to_xml_dict(shost, '', para, False)
    print para['ret_text'],  ('Enable' if arg == '1' else 'Disable'), ('ok' if r else 'Fehler') 
   
# Telefonbuch exportieren   
elif prog == '9':
    para['saction']    = "GetPhoneBook"
    para['sservice']   = "urn:dslforum-org:service:X_AVM-DE_OnTel:1"
    para['controlURL'] = "upnp/control/x_contact"
    para['sparameter'] = """<NewPhonebookID>0</NewPhonebookID>""" 
    para['ret_text']   = "Status Download:"    
    url = response_to_xml_dict(shost, 'Body', para)[0].find('NewPhonebookURL').text
    r = requests.get(url, verify = False)
    if r.ok:
        try:
            f = open('./TelefonbuchFritzbox.xml', 'w')
            f.write(r.content)
            f.close()
            print para['ret_text'], ('ok' if r.ok else 'Fehler') 
        except:
            print 'Fehler beim Schreiben der Datei'
            sys.exit(1)            

# Konfiguration exportieren 
elif prog == '14':
    para['saction']    = "X_AVM-DE_GetConfigFile"
    para['sservice']   = "urn:dslforum-org:service:DeviceConfig:1"
    para['controlURL'] = "upnp/control/deviceconfig"
    para['sparameter'] = """<NewX_AVM-DE_Password>xxxx</NewX_AVM-DE_Password>"""    
    para['ret_text']   = "Status Download:"    
    para['outtag']     = "NewX_AVM-DE_ConfigFileUrl"
    url = response_to_xml_dict(shost, 'Body', para)[0].find(para['outtag']).text
    r = requests.get(url, auth = HTTPDigestAuth(para['user'], para['password']), verify = False)
    if r.ok:
        try:
            f = open('KonfiguratioFritzbox.xml', 'w')
            f.write(r.content)
            f.close()
            print para['ret_text'], ('ok' if r.ok else 'Fehler') 
        except:
            print 'Fehler beim Schreiben der Datei'
            sys.exit(1) 
    else:
        print 'Fehler in Request!'
    
# Funktionsnummer nicht definiert    
else:
    print 'Zum Parameter', prog, 'keine Funktion vorhanden!'

sys.exit(0)    