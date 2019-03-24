<#
    Fritzbox via TR-064 (uPNP-SOAP) steuern und auslesen 
      ------------ @colinardo https://www.administrator.de ---------------
#>
# ====== Variablen =========
$FB_FQDN = "fritz.box"
$USERNAME = 'admin'
$PASSWORD = 'Geheim'
# ====== ENDE Variablen ====

if ($PSVersionTable.PSVersion.Major -lt 3){write-host "ERROR: Minimum Powershell Version 3.0 is required!" -F Yellow; return}

# XML Service-Beschreibungs XML abrufen und Namespace setzen
[xml]$serviceinfo = Invoke-RestMethod -Method GET -Uri "http://$($FB_FQDN):49000/tr64desc.xml"
[System.Xml.XmlNamespaceManager]$ns = new-Object System.Xml.XmlNamespaceManager $serviceinfo.NameTable
$ns.AddNamespace("ns",$serviceinfo.DocumentElement.NamespaceURI)
# Ignore Certificate Errors
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }


# Funktion zum senden eines SOAP Requests
function Execute-SOAPRequest {
    param(
        [Xml]$SOAPRequest,
        [string]$soapactionheader,
        [String]$URL
    )
    try{
        $wr = [System.Net.WebRequest]::Create($URL)
        $wr.Headers.Add('SOAPAction',$soapactionheader)
        $wr.ContentType = 'text/xml; charset="utf-8"'
        $wr.Accept      = 'text/xml'
        $wr.Method      = 'POST'
        $wr.PreAuthenticate = $true
        $wr.Credentials = [System.Net.NetworkCredential]::new($USERNAME,$PASSWORD)

        $requestStream = $wr.GetRequestStream()
        $SOAPRequest.Save($requestStream)
        $requestStream.Close()
        [System.Net.HttpWebResponse]$wresp = $wr.GetResponse()
        $responseStream = $wresp.GetResponseStream()
        $responseXML = [Xml]([System.IO.StreamReader]($responseStream)).ReadToEnd()
        $responseStream.Close()
        return $responseXML
    }catch {
        if ($_.Exception.InnerException.Response){
            throw ([System.IO.StreamReader]($_.Exception.InnerException.Response.GetResponseStream())).ReadToEnd()
        }else{
            throw $_.Exception.InnerException
        }
    }
}

function New-Request {
    param(
        [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$urn,
        [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$action,
        [hashtable]$parameter = @{},
        $Protocol = 'https'
    )
        # SOAP Request Body Template
        [xml]$request = @"
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
    </s:Body>
</s:Envelope>
"@
    # Service auslesen
    $service = $serviceinfo.SelectNodes('//ns:service',$ns) | ?{$_.ServiceType -eq $URN}
    if(!$service){throw "URN does not exist."}
    # Action Element erstellen
    $actiontag = $request.CreateElement('u',$action,$service.serviceType)
    # Parameter erstellen
    $parameter.GetEnumerator() | %{
          $el = $request.CreateElement($_.Key)
          $el.InnerText = $_.Value
          $actiontag.AppendChild($el)| out-null
    }
    # Action Element einfügen
    $request.GetElementsByTagName('s:Body')[0].AppendChild($actiontag) | out-null
    # Send request
    $resp = Execute-SOAPRequest $request "$($service.serviceType)#$($action)" "$($Protocol)://$($FB_FQDN):$(@{$true=$script:secport;$false=49000}[($Protocol -eq 'https')])$($service.controlURL)"
    return $resp
}

# Security-Port (https) abfragen
$script:secport = (New-Request -urn "urn:dslforum-org:service:DeviceInfo:1" -action 'GetSecurityPort' -proto 'http').Envelope.Body.GetSecurityPortResponse.NewSecurityPort

# ----------- Fritz!Box-Funktionen --------------------------
# Fritzbox Reboot
function Invoke-FBReboot(){
    $resp = New-Request -urn 'urn:dslforum-org:service:DeviceConfig:1' -action 'Reboot'
    return $resp.Envelope.Body.InnerText
}
# Basisinformationen und letzte Logeinträge abrufen
function Get-FBInfo(){
    $resp = New-Request -urn 'urn:dslforum-org:service:DeviceInfo:1' -action 'GetInfo'
    return $resp.Envelope.Body.GetInfoResponse
}
# Anruferliste abrufen
function Get-FBCallList(){
    param(
        [int]$maxentries = 999,
        [int]$days = 999
    )
    $resp = New-Request -urn 'urn:dslforum-org:service:X_AVM-DE_OnTel:1' -action 'GetCallList'
    $list = [xml](new-object System.Net.WebClient).DownloadString("$($resp.Envelope.Body.GetCallListResponse.NewCallListURL)&max=$maxentries&days=$days")
    return $list.root.call
}
# WAN-PPP-Info auslesen
function Get-FBWANPPPInfo(){
    $URN = 'urn:dslforum-org:service:WANPPPConnection:1'
    $action = 'GetInfo'
    $resp = New-Request -urn 'urn:dslforum-org:service:WANPPPConnection:1' -action 'GetInfo'
    return $resp.Envelope.Body.GetInfoResponse
}
# Aktuelle DSL-Verbindungsdaten auslesen
function Get-FBWANDSLInterfaceConfig(){
    $resp = New-Request -urn 'urn:dslforum-org:service:WANDSLInterfaceConfig:1' -action 'GetInfo'
    return $resp.Envelope.body.GetInfoResponse
}
# DSL Leitungsstatistik abfragen
function Get-FBWANDSLInterfaceStatistics(){
    $resp = New-Request -urn 'urn:dslforum-org:service:WANDSLInterfaceConfig:1' -action 'GetStatisticsTotal'
    return $resp.Envelope.body.GetStatisticsTotalResponse
}
# DSL-Verbindung trennen
function Invoke-DSLDisconnect(){
    $resp = New-Request -urn 'urn:dslforum-org:service:WANPPPConnection:1' -action 'ForceTermination'
    return $resp.Envelope.body
}
# Portfreigaben abrufen
function Get-FBPortMappings(){
    $resp = New-Request -urn 'urn:dslforum-org:service:WANPPPConnection:1' -action 'GetPortMappingNumberOfEntries' 
    [int]$cnt = $resp.Envelope.Body.GetPortMappingNumberOfEntriesResponse.NewPortMappingNumberOfEntries
    if ($cnt -gt 0){
        0..($cnt - 1) | %{
            $resp = New-Request -urn 'urn:dslforum-org:service:WANPPPConnection:1' -action 'GetGenericPortMappingEntry' -parameter @{NewPortMappingIndex=[string]$_}
            return $resp.Envelope.body.GetGenericPortMappingEntryResponse
        }
    }
}

# Portweiterleitungen anlegen / verändern
function Add-FBPortMapping(){
    param(
        [string]$RemoteHost = '0.0.0.0',
        [Parameter(mandatory=$true)][ValidateRange(1,65535)][uint16]$ExternalPort,
        [Parameter(mandatory=$true)][ValidateSet('TCP','UDP')][string]$Protocol,
        [Parameter(mandatory=$true)][string]$InternalClient,
        [Parameter(mandatory=$true)][ValidateRange(1,65535)][uint16]$InternalPort,
        [bool]$Enabled = $true,
        [Parameter(mandatory=$true)][ValidateNotNullOrEmpty()][string]$Description,
        [string]$LeaseDuration = "0"
    )

    $parameter = [ordered] @{
        NewRemoteHost = $RemoteHost
        NewExternalPort = [string]$ExternalPort
        NewProtocol = $Protocol
        NewInternalPort = [string]$InternalPort
        NewInternalClient = $InternalClient
        NewEnabled = @{$true="1";$false="0"}[$Enabled]
        NewPortMappingDescription = $Description
        NewLeaseDuration = $LeaseDuration
    }
    $resp = New-Request -urn 'urn:dslforum-org:service:WANPPPConnection:1' -action 'AddPortMapping' -parameter $parameter
    return $resp.envelope.body.AddPortMappingResponse
}

# Bestimmte Portweiterleitung löschen

function Delete-FBPortMapping(){
    param(
        [ValidateRange(1,65535)][uint16]$ExternalPort,
        [ValidateSet('TCP','UDP')][string]$Protocol
    )
 
    $parameter = [ordered] @{
        NewRemoteHost = '0.0.0.0'
        NewExternalPort = [string]$ExternalPort
        NewProtocol = $Protocol
    }
    $resp = New-Request -urn 'urn:dslforum-org:service:WANPPPConnection:1' -action 'DeletePortMapping' -parameter $parameter
    return $resp.envelope.body
}

# Rufnummer mit der Wählhilfe wählen
function Dial-FBNumber {
    param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$number
    )   
    $parameter = @{
        'NewX_AVM-DE_PhoneNumber' = $number
    }
    $resp = New-Request -urn 'urn:dslforum-org:service:X_VoIP:1' -action 'X_AVM-DE_DialNumber' -parameter $parameter
    return $resp.envelope.body
}