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
        print('\n1: Response Status= {}'.format(response))
        print('\n2: sservice= {}'.format(para['sservice']))
        print('\n3: saction: {}'.format(para['saction']))
        print('\n4: soap= {}'.format(build_soap(para['saction'], para['sservice'], para['sparameter'])))
    if not response.ok:
        return (False)   
    return response
 
# Ergebnis der SOAP- Aktion aufbereiten 
def response_to_xml_dict(host, tag, para, out=True):
    response = post_soap(host, para)
    try:
        if not response.ok:
            print('HTTP-Fehler: {}'.format(response))
            sys.exit(1)
    except:
        print('Fehler: kein gueltiger Rueckgabewert!')
        sys.exit(1)   
    # bei out=False wird keine Ergebnisausgabe von der Aktion erwartet
    if not out: return response.ok  
    if DEBUG: print('\n5: Response= {}'.format(response.content))  
    # Escapes und Namespaces umwandel/ausfiltern 
    response = response.content.decode('utf-8').replace("&lt;", "<").replace("&gt;", ">")
    response = response.replace("<s:", "<").replace("</s:", "</")
    response = response.replace("<u:", "<").replace("</u:", "</") 
    xml = '<?xml version="1.0" ?>'
    # Ergebnisblock ausfiltern. Das Ergebnis wird im Element 'tag' erwartet - immer 'Body' ausser bei Listen
    xml += response[response.find('<'+tag+'>'):response.find('</'+tag+'>')+len(tag)+3]
    if DEBUG: print('\n6: XML= {}'.format(xml))  
    tree = ElementTree.ElementTree(ElementTree.fromstring(xml)) 
    tag_dict = tree.getroot() 
    return tag_dict


# Security Port ermitteln - Standardport = 49443
def getSecurityPort():
    localpara = para.copy()
    localpara['saction']    = "GetSecurityPort"
    localpara['sservice']   = "urn:dslforum-org:service:DeviceInfo:1"
    localpara['controlURL'] = "upnp/control/deviceinfo"
    localpara['out_text']   = "SSL port:" 
    localpara['outtag']     = "NewSecurityPort"
    return response_to_xml_dict(host, 'Body', localpara)[0].find(localpara['outtag']).text
# externe IP- Adresse abfragen
def getExternalIPAddress():
    localpara = para.copy()
    localpara['saction']    = "GetExternalIPAddress"
    localpara['sservice']   = "urn:dslforum-org:service:WANPPPConnection:1"
    localpara['controlURL'] = "upnp/control/wanpppconn1"
    localpara['ret_text']   = "External IP Address:"
    localpara['outtag']     = "NewExternalIPAddress"
    return response_to_xml_dict(shost, 'Body', localpara)[0].find(localpara['outtag']).text


# GetPortMappingNumberOfEntries abfragen     
def getPortMappingNumberOfEntries():
    localpara = para.copy()
    localpara['saction']    = "GetPortMappingNumberOfEntries"
    localpara['sservice']   = "urn:dslforum-org:service:WANPPPConnection:1"
    localpara['controlURL'] = "upnp/control/wanpppconn1"
    localpara['ret_text']   = "Portmapping number of entries:"
    localpara['outtag']     = "NewPortMappingNumberOfEntries"
    return response_to_xml_dict(shost, 'Body', localpara)[0].find(localpara['outtag']).text
        
# GetGenericPortMappingEntry abfragen     
def getGenericPortMappingEntry():
    localpara = para.copy()
    localpara['saction']    = "GetGenericPortMappingEntry"
    localpara['sservice']   = "urn:dslforum-org:service:WANPPPConnection:1"
    localpara['controlURL'] = "upnp/control/wanpppconn1"
    localpara['sparameter'] = """<NewPortMappingIndex>0</NewPortMappingIndex>"""
    localpara['ret_text']   = "Portmapping entries[0]:"    
    entries = {}
    for e in response_to_xml_dict(shost, 'Body', localpara)[0]:
        entries[e.tag] = e.text
    return entries

# Portmapping enable/disable    
def addPortMapping(arg):
    localpara = para.copy()
    localpara['saction']    = "AddPortMapping"
    localpara['sservice']   = "urn:dslforum-org:service:WANPPPConnection:1"
    localpara['controlURL'] = "upnp/control/wanpppconn1"
    localpara['sparameter'] = """<NewRemoteHost>0.0.0.0</NewRemoteHost>
        <NewExternalPort>80</NewExternalPort>
        <NewProtocol>TCP</NewProtocol>
        <NewInternalPort>80</NewInternalPort>
        <NewInternalClient>192.168.01.100</NewInternalClient>
        <NewPortMappingDescription>HTTP-Server</NewPortMappingDescription>
        <NewLeaseDuration>0</NewLeaseDuration>
        <NewEnabled>""" + arg + """</NewEnabled> """
    localpara['ret_text']   = 'Portmapping:'
    return response_to_xml_dict(shost, '', localpara, False)   

# Anzahl der konfigurierten Rufumleitungen anzeigen        
def getNumberOfDeflections():
    localpara = para.copy()
    localpara['saction']    = "GetNumberOfDeflections"
    localpara['sservice']   = "urn:dslforum-org:service:X_AVM-DE_OnTel:1"
    localpara['controlURL'] = "upnp/control/x_contact"
    localpara['ret_text']   = "Anzahl Rufumleitungen:"
    localpara['outtag']     = "NewNumberOfDeflections"
    return response_to_xml_dict(shost, 'Body', localpara)[0].find(localpara['outtag']).text

# Liste der Rufumleitungen anzeigen    
def getDeflections():
    localpara = para.copy()
    localpara['saction']    = "GetDeflections"
    localpara['sservice']   = "urn:dslforum-org:service:X_AVM-DE_OnTel:1"
    localpara['controlURL'] = "upnp/control/x_contact"
    localpara['ret_text']   = "Anzahl Rufumleitungen:"
    entries = {}
    for item in response_to_xml_dict(shost, 'List', localpara).getchildren(): 
        for e in item:
            entries[e.tag] = e.text
    return entries
    
# Rufumleitung aktivieren/deaktivieren   
def setDeflectionEnable(arg):
    localpara = para.copy()
    localpara['saction']    = "SetDeflectionEnable"
    localpara['sservice']   = "urn:dslforum-org:service:X_AVM-DE_OnTel:1"   
    localpara['controlURL'] = "upnp/control/x_contact"
    localpara['sparameter'] = """<NewDeflectionId>0</NewDeflectionId>
        <NewEnable>""" + arg + """</NewEnable>"""
    localpara['ret_text']   = "SetDeflectionEnable[0]:"
    return response_to_xml_dict(shost, '', localpara, False)
    
# Telefonbuch exportieren   
def getPhoneBook():
    localpara = para.copy()
    localpara['saction']    = "GetPhoneBook"
    localpara['sservice']   = "urn:dslforum-org:service:X_AVM-DE_OnTel:1"
    localpara['controlURL'] = "upnp/control/x_contact"
    localpara['sparameter'] = """<NewPhonebookID>0</NewPhonebookID>""" 
    localpara['ret_text']   = "Status Download:"    
    url = response_to_xml_dict(shost, 'Body', localpara)[0].find('NewPhonebookURL').text
    r = requests.get(url, verify = False)
    if not r.ok:
        return ''
    return r.content   

# Konfiguration exportieren 
def getConfigFile():
    localpara = para.copy()
    localpara['saction']    = "X_AVM-DE_GetConfigFile"
    localpara['sservice']   = "urn:dslforum-org:service:DeviceConfig:1"
    localpara['controlURL'] = "upnp/control/deviceconfig"
    localpara['sparameter'] = """<NewX_AVM-DE_Password>xxxx</NewX_AVM-DE_Password>"""    
    localpara['ret_text']   = "Status Download:"    
    localpara['outtag']     = "NewX_AVM-DE_ConfigFileUrl"
    url = response_to_xml_dict(shost, 'Body', localpara)[0].find(localpara['outtag']).text
    r = requests.get(url, auth = HTTPDigestAuth(localpara['user'], localpara['password']), verify = False)
    if not r.ok:
        return ''
    return r.content   


if __name__ == "__main__":   
    # ************************ main ********************************
    try:
        prog = sys.argv[1]
    except:
        print('TR-049.py [1..n] [0|1] [password] erwartet.')
        sys.exit()
    try:
        arg = sys.argv[2]
    except:
        arg = '0'
    if len(sys.argv) > 2:
        para['password'] = sys.argv[3]
    
    # Security Port ermitteln - Standardport = 49443
    if prog == '1':
        r = getSecurityPort()
        print("SSL port: {}".format(r))
    
    # externe IP- Adresse abfragen     
    elif prog == '2':
        r = getExternalIPAddress()
        print("External IP Address: {}".format(r))
        
    # GetPortMappingNumberOfEntries abfragen     
    elif prog == '3':
        r= getPortMappingNumberOfEntries()
        print("Portmapping number of entries: {}".format(r))

        
    # GetGenericPortMappingEntry abfragen     
    elif prog == '4':
        r = getGenericPortMappingEntry()  
        print("Portmapping entries[0]:")
        for k in r:
            print("{} = {}".format(k,r[k]))

    # Portmapping enable/disable    
    elif prog == '5':
        r = addPortMapping(arg)  
        print('Portmapping: {} {}'.format(('Enable' if arg == '1' else 'Disable'), ('ok' if r else 'Fehler')))

    # Anzahl der konfigurierten Rufumleitungen anzeigen        
    elif prog == '6':
        r = getNumberOfDeflections()
        print("Anzahl Rufumleitungen: {}".format(r))

    # Liste der Rufumleitungen anzeigen    
    elif prog == '7':
        r = getDeflections()
        for k in r:
            print("{} = {}".format(k,r[k]))
    
    # Rufumleitung aktivieren/deaktivieren   
    elif prog == '8':
        r = setDeflectionEnable(arg)
        print('SetDeflectionEnable[0]: {} {}'.format(('Enable' if arg == '1' else 'Disable'), ('ok' if r else 'Fehler')))
    
    # Telefonbuch exportieren   
    elif prog == '9':
        r = getPhoneBook()
        if len(r) > 0:
            try:
                f = open('./TelefonbuchFritzbox.xml', 'w')
                f.write(r)
                f.close()
                print('Status Download: ok')
            except:
                print('Fehler beim Schreiben der Datei')
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
        r = getConfigFile()
        if len(r) > 0:
            try:
                f = open('KonfiguratioFritzbox.xml', 'w')
                f.write(r)
                f.close()
                print('Status Download: ok')
            except:
                print('Fehler beim Schreiben der Datei')
                sys.exit(1) 
        else:
            print('Fehler in Request!')
        
    # Funktionsnummer nicht definiert    
    else:
        print('Zum Parameter {} keine Funktion vorhanden!'.format(prog))

    sys.exit(0)    