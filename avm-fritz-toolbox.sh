#!/bin/bash
#------------------------------------------------------------------------------
# avm-fritz-toolbox.sh
#
# Copyright (c) 2016-2019 Marcus Roeckrath, marcus(dot)roeckrath(at)gmx(dot)de
#
# Creation:     2016-09-04
# Last Update:  2019-02-22
# Version:      2.2.16
#
# Usage:
#
# avm-fritz-toolbox.sh [command] [option [value]] .. [option [value]]
#
# For full help use: avm-fritz-toolbox.sh --help
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#------------------------------------------------------------------------------

# adds, deletes, enables or disables specified port forwarding on fritzbox
# shows list of port forwardings
# shows external ipv4/ipv6 address
# reboots or reconnects the fritzbox
# infos about fritzbox, wlan, storage, upnp, media server, ddns and firmware updates
# switches wlans, ftp, smb, upnp and media server on or off
# status of internet connection
# saves fritzbox configuration
# performs self defined soap request defined in a file

version="2.2.16"
copyright="Version: ${version} ; Copyright: (2016-2019) Marcus Roeckrath ; Licence: GPL2"
contact="                                         marcus(dot)roeckrath(at)gmx(dot)de"

# Exitcodes
error_0="Success"
error_1="Error on communication with fritzbox"
error_2="Fritzbox not reachable"
error_3="Command curl missing"
error_4="Unknown or missing command"
error_5="Unknown option"
error_6="Wrong or missing parameter"
error_7="Configuration error"
error_8="No internet connection"
error_9="No external IPv4 address"
error_10="No external IPv6 address or prefix"
error_11="Function only available in experimental mode"
error_12="SOAP request: File not given/not existing or options not given on command line"
error_13="\${HOME} environment variable is not set or target file for soap sample file not given"
error_14="not found on fritzbox"
error_15="Error downloading fritzbox configuration file"

# debug mode true/false
debug=false
if ${debug:-false}
then
    exec 2>/tmp/avm-fritz-toolbox-$$.log
    set -x
    ask_debug=true
    export ask_debug
fi

if [ -n "${HOME}" ]
then
    configfile=${HOME}/.avm-fritz-toolbox
    soapfile=${HOME}/avm-fritz-toolbox.samplesoap
    netrcfile=${HOME}/.netrc
fi

#. /var/install/include/eislib

# Begin settings section ---------------------------------------------
#
# Do not change the default values here, create a configuration file with
#
# avm-fritz-toolbox.sh writeconfig
#
# in your Home directory; HOME envrionment variable has to be set!
#
# Address (IP or FQDN)
FBIP="192.168.0.1"
# SOAP port; do not change
FBPORT="49000"
# SSL SOAP port; will be read from the fritzbox later in this script.
FBPORTSSL="49443"

# Fixes for faulty fritzboxes
FBREVERSEPORTS="false"
FBREVERSEFTPWAN="false"

# Authentification settings
user="dslf-config"
password="xxxxx"

# Save fritzbox configuration settings
# Absolute path fritzbox configuration file; not empty.
fbconffilepath="/root"
# Prefix/suffix of configuration file name.
# Model name, serial number, firmware version and date/time stamp will be added.
fbconffileprefix="fritzbox"
fbconffilesuffix="config"
# Password for fritzbox configuration file, could be empty.
fbconffilepassword="xxxxx"

# Default port forwarding settings
# do not change
new_remote_host=""
# Source port
new_external_port="80"
# Protocol TCP or UDP
new_protocol="TCP"
# Target port
new_internal_port="80"
# Target ip
new_internal_client="192.168.0.213"
# Port forward enabled (1) or disabled (0)
new_enabled="1"
# Description (not empty)
new_port_mapping_description="http forward for letsencrypt"
# do not change
new_lease_duration="0"
#
# End settings section -----------------------------------------------

# read settings from ${HOME}/.avm-fritz-toolbox overriding above default values
readconfig () {
    if [ -n "${configfile}" ] && [ -f "${configfile}" ]
    then
        . "${configfile}"
    fi
}

# check settings
checksettings () {
    configfault=false
    if ! (echo "${FBIP}" | grep -Eq "^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])){3}$") &&
       ! (echo "${FBIP}" | grep -Eq "^[[:alnum:]]([-]*[[:alnum:]])*(\.[[:alnum:]]([-]*[[:alnum:]])*)*$")
    then
        configfault=true
        faultyparameters="FBIP=\"${FBIP}\""
    fi
    if ! ((echo "${FBPORT}" | grep -Eq "^[[:digit:]]{1,5}$") && \
          [ "${FBPORT}" -ge 0 ]  && [ "${FBPORT}" -le 65535 ])
    then
        configfault=true
        faultyparameters="${faultyparameters}\nFBPORT=\"${FBPORT}\""
    fi
    if ! ((echo "${FBPORTSSL}" | grep -Eq "^[[:digit:]]{1,5}$") && \
          [ "${FBPORTSSL}" -ge 0 ]  && [ "${FBPORTSSL}" -le 65535 ])
    then
        configfault=true
        faultyparameters="${faultyparameters}\nFBPORTSSL=\"${FBPORTSSL}\""
    fi
    if [ "${FBREVERSEPORTS}" != "true" ] && [ "${FBREVERSEPORTS}" != "false" ]
    then
        configfault=true
        faultyparameters="${faultyparameters}\nFBREVERSEPORTS=\"${FBREVERSEPORTS}\""
    fi
    if [ "${FBREVERSEFTPWAN}" != "true" ] && [ "${FBREVERSEFTPWAN}" != "false" ]
    then
        configfault=true
        faultyparameters="${faultyparameters}\nFBREVERSEFTPWAN=\"${FBREVERSEFTPWAN}\""
    fi
    if [ -z "${fbconffilepath}" ] || [ ! -d "${fbconffilepath}" ]
    then
        configfault=true
        faultyparameters="${faultyparameters}\nfbconffilepath=\"${fbconffilepath}\""
    fi
    if ! ((echo "${new_external_port}" | grep -Eq "^[[:digit:]]{1,5}$") && \
          [ "${new_external_port}" -ge 0 ]  && [ "${new_external_port}" -le 65535 ])
    then
        configfault=true
        faultyparameters="${faultyparameters}}\nnew_external_port=\"${new_external_port}\""
    fi
    if [ "${new_protocol}" != "TCP" ] && [ "${new_protocol}" != "UDP" ]
    then
        configfault=true
        faultyparameters="${faultyparameters}\nnew_protocol=\"${new_internal_port}\""
    fi
    if ! ((echo "${new_internal_port}" | grep -Eq "^[[:digit:]]{1,5}$") && \
          [ "${new_internal_port}" -ge 0 ]  && [ "${new_internal_port}" -le 65535 ])
    then
        configfault=true
        faultyparameters="${faultyparameters}\nnew_internal_port=\"${new_internal_port}\""
    fi
    if ! (echo "${new_internal_client}" | grep -Eq "^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])){3}$")
    then
        configfault=true
        faultyparameters="${faultyparameters}\nnew_internal_client=\"${new_internal_client}\""
    fi
    if [ "${new_enabled}" != "0" ] && [ "${new_enabled}" != "1" ]
    then
        configfault=true
        faultyparameters="${faultyparameters}\nnew_enabled=\"${new_enabled}\""
    fi
    if [ -z "${new_port_mapping_description}" ]
    then
        configfault=true
        faultyparameters="${faultyparameters}\nnew_port_mapping_description is empty"
    fi
    if [ "${configfault}" = "true" ]
    then
        if [ -n "${1}" ]
        then
            mecho --error "The configuration file ${1} is faulty!"
        else
            mecho --error "Script default configuration is faulty!"
        fi
        mecho --warn "Faulty parameters:\n${faultyparameters}"
        exit_code=7
        remove_debugfbfile
        exit 7
    fi
}

# Use ${HOME}/.netrc for authentification if present
# avoiding that the password could be seen in environment or process list.
# Rights on ${HOME}/.netrc has to be 0600 (chmod 0600 ${HOME}/.netrc).
# Content of a line in this file for your fritzbox should look like:
# machine <ip of fritzbox> login <user> password <password>
determineauthmethod () {
    if [ -n "${netrcfile}" ] && [ -f "${netrcfile}" ] &&
       ((grep -q " ${FBIP} " "${netrcfile}") || (grep -q " ${FBIP}$" "${netrcfile}"))
    then
        authmethod="--netrc"
    else
        authmethod="-u ${user}:${password}"
    fi
}

# write sample configuration file to ${HOME}/.avm-fritz-toolbox
writeconfig () {
cat > "${configfile}" << EOF
# Configuration file for avm-fritz-toolbox.sh
#
# Fritzbox settings
# Address (IP or FQDN)
FBIP="${FBIP}"
# SOAP port; do not change
FBPORT="${FBPORT}"
# SSL SOAP port; will be read from the fritzbox in the script.
FBPORTSSL="${FBPORTSSL}"

# Fixes for faulty fritzboxes / fritzbox firmwares
# Maybe fixed in firmware version 6.80.
# It seams that some of them reverses the values of "NewInternalPort" and
# "NewExternalPort" in function "GetGenericPortMapEntry" of "WANIPConnection:1"
# resp. "WANPPPConnection:1".
# Set this to true if you are affected."
FBREVERSEPORTS="${FBREVERSEPORTS}"
# It seams that some of them reverses the values of "NewFTPWANEnable" and
# "NewFTPWANSSLOnly" in function "SetFTPWANServer" of "X_AVM-DE_Storage:1".
# Set this to true if you are affected."
FBREVERSEFTPWAN="${FBREVERSEFTPWAN}"

# Authentification settings
# dslf-config is the standard user defined in TR-064 with web login password.
# You can use any other user defined in your fritzbox with sufficient rights.
#
# Instead of writing down your password here it is safer to use \${HOME}/.netrc
# for the authentification data avoiding that the password could be seen in
# environment or process list.
# Rights on \${HOME}/.netrc has to be 0600: chmod 0600 \${HOME}/.netrc
# Content of a line in this file for your fritzbox should look like:
# machine <ip of fritzbox> login <user> password <password>
# f. e.
# machine ${FBIP} login ${user} password ${password}
# The fritzbox address has to be given in the same type (ip or fqdn) in
# \${HOME}/.avm-fritz-toolbox or on command line parameter --fbip and \${HOME}/.netrc.
user="${user}"
password="${password}"

# Save fritzbox configuration settings
# Absolute path to fritzbox configuration file; not empty.
fbconffilepath="${fbconffilepath}"
# Prefix/suffix of configuration file name.
# Model name, serial number, firmware version and date/time stamp will be added.
# "_" is added to prefix and "." is added to suffix automatically so that name
# will be: prefix_<model>_<serialno>_<firmwareversion>_<date_time>.suffix
fbconffileprefix="${fbconffileprefix}"
fbconffilesuffix="${fbconffilesuffix}"
# Password for fritzbox configuration file, could be empty.
# Configuration files without password could restored to
# the same fritzbox not to a different fritzbox.
fbconffilepassword="${fbconffilepassword}"

# Default port forwarding settings
# do not change
new_remote_host="${new_remote_host}"
# Source port
new_external_port="${new_external_port}"
# Protocol TCP or UDP
new_protocol="${new_protocol}"
# Target port
new_internal_port="${new_internal_port}"
# Target ip address
new_internal_client="${new_internal_client}"
# Port forward enabled (1) or disabled (0)
new_enabled="${new_enabled}"
# Description (not empty)
new_port_mapping_description="${new_port_mapping_description}"
# do not change
new_lease_duration="${new_lease_duration}"
EOF
}

# write sample soap file to ${HOME}/avm-fritz-toolbox.samplesoap or
# to file given on command line with full path
writesoapfile () {

type="https"
descfile="tr64desc.xml"
controlURL="deviceconfig"
serviceType="DeviceConfig:1"
action="X_AVM-DE_GetConfigFile"
data="
       <NewX_AVM-DE_Password>abcdef</NewX_AVM-DE_Password>
     "
search=""
# read settings from ${HOME}/avm-fritz-toolbox.samplesoap
if [ -n "${soapfile}" ] && [ -f "${soapfile}" ]
then
    . "${soapfile}"
    found=false
    soapfiletemp=$(mktemp)
    # Special construct to avoid loosing last line if there is no newline on it
    while read soapfileline || [ -n "${soapfileline}" ]
    do
        if [ "${soapfileline}" = "# [GENERAL_CONFIGURATION]" ]
        then
            found=true
            continue
        fi
        if [ "${found}" = "true" ]
        then
            echo "${soapfileline}" >> "${soapfiletemp}"
        fi
    done < "${soapfile}"
fi

cat > "${soapfile}" << EOF
# This files describes a SOAP request which can be used by the
# "avm-fritz-toolbox.sh mysoaprequest <soapfile>" command.
#
# More infos on
# https://avm.de/service/schnittstellen
# http://www.fhemwiki.de/wiki/FRITZBOX
#
# Never change the names of the variables!
#
# Look at "https://avm.de/service/schnittstellen" for documents
# on the TR-064 interface.
#
#
# Type of SOAP-Request: http or https
# Https SOAP Request are allways user authenticated.
# Most functions needs https requests.
# All http soap request are available through https also while
# https soap request needs https type allways.
# On commandline use --SOAPtype <https|http>
#
type="${type}"
#
#
# Name of description file normally tr64desc.xml or igddesc.xml
# On commandline use --SOAPdescfile <xmlfilename>
#
descfile="${descfile}"
#
#
# Download desired descfile from above from your fritzbox.
#
# curl http://<fritzbox-ip>:49000/tr64desc.xml
#
# or use
#
# avm-fritz-toolbox.sh showxmlfile tr64desc.xml
#
# Search in this file for the service you want to use, f. e.
#
# <service>
# <serviceType>urn:dslforum-org:service:DeviceConfig:1</serviceType>
# <serviceId>urn:DeviceConfig-com:serviceId:DeviceConfig1</serviceId>
# <controlURL>/upnp/control/deviceconfig</controlURL>
# <eventSubURL>/upnp/control/deviceconfig</eventSubURL>
# <SCPDURL>/deviceconfigSCPD.xml</SCPDURL>
# </service>
#
# Put here last part of the path (most right) or full path from the
# <controlURL>-line without xml tags.
# On commandline use --SOAPcontrolURL <URL>
#
controlURL="${controlURL}"
#
#
# Put here last part (most right, must include ":<number>") or
# complete content from the <serviceType>-line without xml tags.
# On commandline use --SOAPserviceType <service type>
#
serviceType="${serviceType}"
#
#
# Download the file from the <SCPDURL>-line from your fritzbox f. e.
#
# curl http://<fritzbox-ip>:49000/deviceconfigSCPD.xml
#
# or use
#
# avm-fritz-toolbox.sh showxmlfile deviceconfigSCPD.xml
#
# Search in this file for the action you want to use, f. e.
#
# <action>
# <name>X_AVM-DE_GetConfigFile</name>
# <argumentList>
# <argument>
# <name>NewX_AVM-DE_Password</name>
# <direction>in</direction>
# <relatedStateVariable>X_AVM-DE_Password</relatedStateVariable>
# </argument>
# <argument>
# <name>NewX_AVM-DE_ConfigFileUrl</name>
# <direction>out</direction>
# <relatedStateVariable>X_AVM-DE_ConfigFileUrl</relatedStateVariable>
# </argument>
# </argumentList>
# </action>
#
# Put here the name of the action (function) without xml tags.
# On commandline use --SOAPaction <function name>
#
action="${action}"
#
#
# Put here one line for every argument which has direction "in" without xml tags
#
# data="
#       <in_argument_name_1>value_1</in_argument_name_1>
#       <in_argument_name_2>value_2</in_argument_name_2>
#       ...
#       <in_argument_name_n>value_2</in_argument_name_2>
#      "
#
# or if there are no "in" arguments.
#
# data=""
#
# Take the <name>- and not the <relatedStateVariable>-line for every argument.
# Arguments mostly but not allways are "New" prefixed.
# On commandline use --SOAPdata "<function data>" (space separated enclosed in parenthesis)
#
data="${data}"
#
#
# Put here one line for every argument having direction "out" without xml tags
#
# search="
#         <out_argument_name_1>
#         <out_argument_name_2>
#         ...
#         <out_argument_name_n>
#        "
#
# which you want to see as filtered output. Take those arguments you want to see in
# output f. e.
#
# search="NewX_AVM-DE_ConfigFileUrl"
#
# or if you want to see all arguments in filtered output.
#
# search="all"
#
# If you want to see complete unfiltered raw output set
#
# search=""
#
# Filtered output format: out_argument_name_X|value
#
# Filtered output for a multiline out argument displays the first line only.
#
# Take the <name>- and not the <relatedStateVariable>-line for every choosen argument.
# Arguments mostly but not allways are "New" prefixed.
# On commandline use --SOAPsearch "<search text>|all" (space separated enclosed in parenthesis)
#
search="${search}"
#
#
# Put here any text you want to see as header line in output. If not empty
# a standard device string like "(FRITZ!Box 7490 113.06.83@192.168.178.1)"
# will be added automatically.
#
# title=""
# title="my text"
#
title=""
#
#
# You can put in all parameter="value" lines from the config file here,
# overriding the settings from the config file \${HOME}/$(basename "${configfile}") f. e.
#
# FBIP="192.168.178.1"
#
# Put your settings below the "# [GENERAL_CONFIGURATION]" line.
# Never delete or modify the  "# [GENERAL_CONFIGURATION]" line. If you do so you will loose
# these additional setting lines when updating a soap file with the writesoapfile command.
#
# [GENERAL_CONFIGURATION]
EOF

if [ -n "${soapfiletemp}" ] && [ -f "${soapfiletemp}" ]
then
    cat "${soapfiletemp}" >> "${soapfile}"
    rm -f "${soapfiletemp}"
fi
}

# Output debugfbfile
output_debugfbfile () {
    if [ -f "${debugfbfile}" ]
    then
        echo
        mecho --info "Debug output of communication with fritzbox"
        cat "${debugfbfile}"
        echo "------------------------------------------------------------------"
        echo "Device        : ${debugdevice}"
        echo "Command line  : ${commandline}" 
        echo "Script version: ${version}" 
        echo "Errorlevel    : ${exit_code}"
        eval error='$'error_"${exit_code}"
        echo "Errorcode     : ${error}"
        echo "------------------------------------------------------------------"
        rm -f "${debugfbfile}"
    fi
}

# Remove debugfbfile
remove_debugfbfile () {
    if [ -f "${debugfbfile}" ]
    then
        rm -f "${debugfbfile}"
    fi
}

# Convert boolean values to yes/no
convert_yes_no () {
    case "${1}"
    in
        0)
            echo "no"
        ;;
        1)
            echo "yes"
        ;;
        *)
            echo "?"
        ;;
    esac
}

# Convert html entities
convert_html_entities () {
    echo "$(echo "${1}" | sed -e 's#\&lt;#<#g' -e 's#\&gt;#>#g' -e 's#\&amp;#\&#g' -e 's#\&quot;#"#g' -e "s#\&apos;#'#g")"
}

# Multiline output
# $1            : Comment on first line
# $2            : Comment on additional lines
# $3 and higher : Output text enclosed in "" if there are special chars contained
multilineoutput () {
    comment="${1}"
    shift
    secondcomment="${1}"
    shift
    if [ "${secondcomment}" = "" ]
    then
        secondcomment="$(echo ${comment} | sed 's/./ /g')"
    fi
    maxlength=$(expr ${_EISLIB_SCREENSIZE_X} - ${#comment} - 1)
    for word in $*
    do
        if [ -z "${output}" ]
        then
            output="${word}"
        else
            length=$(expr ${#output} + ${#word} + 1)
            if [ ${length} -le ${maxlength} ]
            then
                output="${output} ${word}"
            else
                echo "${comment} ${output}"
                comment="${secondcomment}"
                output="${word}"
            fi
        fi
    done
    if [ -n "${output}" ]
    then
        echo "${comment} ${output}"
    fi
    output=""
}

# get url and urn from the fritzbox description files for the desired command
get_url_and_urn () {
    local descfile="${1}"
    local name_controlURL="${2}"
    local name_serviceType="${3}"
    local response=$(${CURL_BIN} -s "http://${FBIP}:${FBPORT}/${descfile}")
    control_url=$(echo "${response}" | \
        grep -Eo "<controlURL>"'([a-zA-Z0-9/]*)'"${name_controlURL}</controlURL>" | \
        sed -e 's/^<controlURL>//' -e 's/<\/controlURL>.*$//')
    urn=$(echo "${response}" | \
        grep -Eo "<serviceType>"'([a-zA-Z:-]*)'"${name_serviceType}</serviceType>" | \
        sed  -e 's/^<serviceType>//' -e 's/<\/serviceType>.*$//')
    if [ "${debugfb:-false}" = "true" ]
    then
        (
            echo "------------------------------------------------------------------"
            echo "Get url and urn from desc file"
            echo
            echo "fbip            : ${FBIP}"
            echo
            echo "fbport          : ${FBPORT}"
            echo
            echo "desc file       : ${descfile}"
            echo
            echo "name_controlURL : ${name_controlURL}"
            echo
            echo "name_serviceType: ${name_serviceType}"
            echo
            echo "control_url     : ${control_url}"
            echo
            echo "urn             : ${urn}"
        ) >> ${debugfbfile}
    fi
}

# quit script immediately from soap request function subshell
# call: kill -s TERM $TOP_PID
quitmessagefile="/tmp/avm-fritz-toolbox.sh.quitmessagefile"
trap "quit_from_soap_request" TERM
export TOP_PID=$$
quit_from_soap_request () {
    mecho --error "$(cat ${quitmessagefile})"
    rm -f "${quitmessagefile}"
    exit_code=1
    output_debugfbfile
    exit 1
}

# execute a http soap command
execute_http_soap_request () {
    local function="${1}"
    local data="${2}"
    local response
    response=$(${CURL_BIN} -s -m 5 \
                 "http://${FBIP}:${FBPORT}${control_url}" \
                 -H "Content-Type: text/xml; charset=\"utf-8\"" \
                 -H "SoapAction:${urn}#${function}" \
                 -d "<?xml version=\"1.0\" encoding=\"utf-8\"?>
                 <s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">
                 <s:Body>
                 <u:${function} xmlns:u=\"${urn}\">
                 ${data}
                 </u:${function}>
                 </s:Body>
                 </s:Envelope>")
    if [ "${debugfb:-false}" = "true" ]
    then
        (
            echo "------------------------------------------------------------------"
            echo "SOAP request (http)"
            echo
            echo "fbip    : ${FBIP}"
            echo
            echo "fbport  : ${FBPORT}"
            echo
            echo "function: ${function}"
            echo
            echo "data    : ${data}"
            echo
            echo "response: ${response}"
        ) >> ${debugfbfile}
    fi
    if [ -z "${response}" ]
    then
        echo "No (http) response from fritzbox on port ${FBPORT}" > ${quitmessagefile}
        kill -s TERM $TOP_PID
    else
        echo "${response}"
    fi
}

# execute a https soap command
execute_https_soap_request () {
    local function="${1}"
    local data="${2}"
    local response
    response=$(${CURL_BIN} -s -m 5 -k --anyauth ${authmethod} \
                 --capath /usr/local/ssl/certs \
                 "https://${FBIP}:${FBPORTSSL}${control_url}" \
                 -H "Content-Type: text/xml; charset=\"utf-8\"" \
                 -H "SoapAction:${urn}#${function}" \
                 -d "<?xml version=\"1.0\" encoding=\"utf-8\"?>
                 <s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">
                 <s:Body>
                 <u:${function} xmlns:u=\"${urn}\">
                 ${data}
                 </u:${function}>
                 </s:Body>
                 </s:Envelope>")
    if [ "${debugfb:-false}" = "true" ]
    then
        (
            echo "------------------------------------------------------------------"
            echo "SOAP request (https)"
            echo
            echo "fbip      : ${FBIP}"
            echo
            echo "fbsslport : ${FBPORTSSL}"
            echo
            echo "function  : ${function}"
            echo
            echo "data      : ${data}"
            echo
            echo "response  : ${response}"
        ) >> ${debugfbfile}
    fi
    if [ -z "${response}" ]
    then
        echo "No (https) response from fritzbox on port ${FBPORTSSL}" > ${quitmessagefile}
        kill -s TERM $TOP_PID
    else
        echo "${response}"
    fi
}

# parse xml response from fritzbox
parse_xml_response () {
    local response="${1}"
    local search="${2}"
    local found
    found=$(echo "${response}" | sed -ne "s#[ \t]*</*${search}>[ \t]*##gp")
    echo "${found}"
    if [ "${debugfb:-false}" = "true" ]
    then
        (
            echo "------------------------------------------------------------------"
            echo "Parse fritzbox response"
            echo
            echo "response: ${response}"
            echo
            echo "search  : ${search}"
            echo
            echo "found   : ${found}"
        ) >> ${debugfbfile}
    fi
}

# help page
usage () {
    if [ "${1}" = "commandline" ] && [ -n "${commandline}" ]
    then
        mecho --error "Command line: ${commandline}"
    fi
    echo "Fritzbox TR-064 command line interface"
    echo "${copyright}"
    echo "${contact}"
    if [ "${1}" = "version" ]
    then
        return 0
    fi
    echo "Usage           : $(basename ${0}) command [option [value]] .. [option [value]]"
    echo
    echo "Commands:"
    echo "add             : Adds a (predefined) port forward."
    echo "del             : Deletes a (predefined) port forward."
    echo "enable          : Activates a previous disabled (predefined) port forward."
    echo "                  If not yet present in fritzbox port forward will be added enabled."
    echo "disable         : Deactivates a (predefined) port forward if present in fritzbox."
    echo "                  If not yet present in fritzbox port forward will be added disabled."
    echo "show            : Shows all port forwardings whether set by authorized user or upnp."
    echo "extip           : Shows the external IP v4 and v6 addresses."
    echo "extipv4         : Shows the external IP v4 address."
    echo "extipv6         : Shows the external IP v6 address."
    echo "connstat        : Status of internet connection."
    echo "ddnsinfo        : Information/Status of dynamic dns service."
    echo "wlancount       : Prints number and type of available wlans."
    echo "wlanswitch (*)  : Activates/deactivates wlan global acting like button on fritzbox."
    echo "wlan?switch (*) : Activates/deactivates wlan (2.4GHz, 5 GHz|guest wlan, guest wlan); ? = 1, 2 or 3."
    echo "wlan?info       : Information/Status of wlan (2.4GHz, 5 GHz|guest wlan, guest wlan); ? = 1, 2 or 3."
    echo "dectinfo        : Shows dect telephone list."
    echo "deflectionsinfo : Shows telephone deflections list."
    echo "homeautoinfo    : Shows informations from home automation/smart home devices."
    echo "homeautoswitch \"<ain>\" (*)"
    echo "                : Switches home automation switch given by ain."
    echo "homepluginfo    : Shows homeplug/powerline devices list."
    echo "hostsinfo       : Shows hosts list."
    echo "autowolswitch <mac>"
    echo "                : Activates/Deactivates Auto WOL configuration of client given by mac address."
    echo "autowolinfo <mac>"
    echo "                : Shows Auto WOL configuration of client given by mac address."
    echo "wolclient <mac> : Wake on lan client given by mac address."
    echo "ftpswitch       : Activates/deactivates ftp server."
    echo "ftpwanswitch    : Activates/deactivates ftp wan server."
    echo "ftpwansslswitch : Activates/deactivates ssl only on ftp wan server."
    echo "smbswitch       : Activates/deactivates smb server."
    echo "nasswitch       : Activates/deactivates nas server (local ftp and smb)."
    echo "storageinfo     : Information/Status of ftp and smb server."
    echo "upnpswitch      : Activates/deactivate of upnp status messages."
    echo "mediaswitch     : Activates/deactivate of media server."
    echo "upnpmediainfo   : Information/Status of upnp media server."
    echo "taminfo         : Information/Status of answering machine."
    echo "tamcap          : Shows capacity of answering machine."
    echo "tamswitch <index> (*)"
    echo "                : Activates/Deactivates answering machine given by index"
    echo "                  (0-9; depending on firmware version and model)."
    echo "reconnect       : Reconnects to internet."
    echo "reboot          : Reboots the fritzbox."
    echo "savefbconfig    : Stores the fritzbox configuration to"
    echo "                  ${fbconffilepath}/${fbconffileprefix}_<model>_<serialno>_<firmwareversion>_<date_time>.${fbconffilesuffix}."
    echo "updateinfo      : Informations about fritzbox firmware updates."
    echo "tr69info        : Informations about provider managed updates via TR-069."
    echo "deviceinfo      : Informations about the fritzbox (model, firmware, ...)."
    echo "devicelog       : Shows fritzbox log formatted or raw."
    echo "listxmlfiles    : Lists all available xml files."
    echo "showxmlfile [<xmlfilename>]"
    echo "                : Shows xml file from fritzbox."
    echo "mysoaprequest [<fullpath>/]<file>|<command line parameters>"
    echo "                : Makes SOAP request defined in <file> or from command line parameters."
    if [ -n "${configfile}" ]
    then
        echo "writeconfig     : Writes sample configuration file to ${configfile}."
    else
        echo "writeconfig     : Writes sample configuration file to \${HOME}/.avm-fritz-toolbox."
    fi
    echo "writesoapfile [<fullpath>/<file>]"
    echo "                : Writes sample SOAP configuration file to"
    if [ -n "${soapfile}" ]
    then
        echo "                  specified file or to sample file ${soapfile}."
    else
        echo "                  specified file."
    fi
    echo
    echo "Optional parameters:"
    echo "Parameter                            Used by commands"
    echo "--fbip <ip address>|<fqdn>           all but writeconfig and writesoapfile"
    echo "--description \"<text>\"               add, enable, disable"
    echo "--extport <port number>              add, enable, disable, del"
    echo "--intclient <ip address>             add, enable, disable"
    echo "--intport <port number>              add, enable, disable"
    echo "--protocol <TCP|UDP>                 add, enable, disable, del"
    echo "--active                             add, *switch"
    echo "--inactive                           add, *switch"
    echo "--searchhomeautoain \"<text>\"         homeautoinfo"
    echo "--searchhomeautodeviceid \"<text>\"    homeautoinfo"
    echo "--searchhomeautodevicename \"<text>\"  homeautoinfo"
    echo "               \"<text>\" in search parameters could be text or Reg-Exp."
    echo "--ftpwansslonlyon (**)               ftpwanswitch"
    echo "--ftpwansslonlyoff (**)              ftpwanswitch"
    echo "--ftpwanon (**)                      ftpwansslswitch"
    echo "--ftpwanoff (**)                     ftpwansslswitch"
    echo "--mediaon (**)                       upnpswitch"
    echo "--mediaoff (**)                      upnpswitch"
    echo "--upnpon (**)                        mediaswitch"
    echo "--upnpoff (**)                       mediaswitch"
    echo "          (**) Previous status will be preserved if"
    echo "               *on|off parameter is not given on the command line."
    echo "--showfritzindexes                   show, deflectionsinfo,"
    echo "                                     homeautoinfo, homepluginfo, hostsinfo"
    echo "--rawdevicelog                       devicelog"
    echo "--soapfilter                         showxmlfile"
    echo "--fbconffilepath \"<abs path>\"        savefbconfig"
    echo "--fbconffileprefix \"<text>\"          savefbconfig"
    echo "--fbconffilesuffix \"<text>\"          savefbconfig"
    echo "--fbconffilepassword \"<text>\"        savefbconfig"
    echo
    echo "Explanations for these parameters could be found in the SOAP sample file."
    echo "--SOAPtype <https|http>              mysoaprequest"
    echo "--SOAPdescfile <xmlfilename>         mysoaprequest"
    echo "--SOAPcontrolURL <URL>               mysoaprequest"
    echo "--SOAPserviceType <service type>     mysoaprequest"
    echo "--SOAPaction <function name>         mysoaprequest"
    echo "--SOAPdata \"<function data>\"         mysoaprequest"
    echo "--SOAPsearch \"<search text>|all\"     mysoaprequest"
    echo "--SOAPtitle \"<text>\"                 mysoaprequest"
    echo
    echo "--experimental                       Enables experimental commands (*)."
    echo
    echo "--debugfb                            Activate debug output on fritzbox communication."
    echo
    echo "version|--version                    Prints version and copyright informations."
    echo "help|--help|-h                       Prints help page."
    echo
    echo "Necessary parameters not given on the command line are taken from default"
    echo "values or ${configfile}."
    if [ "${1}" = "fullhelp" ]
    then
        echo
        echo "If modifying an existing port forwarding entry with the add, enable or disable commands"
        echo "the values for extport, intclient and protocol has to be entered in exact the same"
        echo "way as they are stored in the port forwarding entry on the fritzbox! Differing values"
        echo "for intport, description and active/inactive status could be used and will change"
        echo "these values in the port forwarding entry on the fritzbox."
        echo
        echo "If deleting an port forwarding entry on the fritzbox the values for extport and protocol"
        echo "has to be entered in exact the same way as they are stored in the port forwarding entry"
        echo "on the fritzbox."
        echo
        echo "The script reads default values for all variables from ${configfile}."
        echo
        echo "The script can use the fritzbox authentification data from ${netrcfile}"
        echo "which has to be readable/writable by the owner only (chmod 0600 ${netrcfile})."
        echo "Put into this file a line like: machine <address of fritzbox> login <username> password <password>"
        echo "f. e.: machine ${FBIP} login ${user} password ${password}"
        echo "The fritzbox address has to be given in the same type (ip or fqdn) in"
        echo "${configfile} or on command line parameter --fbip and ${netrcfile}."
        echo
        echo "Warning:"
        echo "If adding or deleting port forwardings in the webgui of your fritzbox please"
        echo "reboot it afterwards. Otherwise the script will see an incorrect port forwarding count"
        echo "through the TR-064 interface ending up in corrupted port forwarding entries."
    fi
}

commandline="${*}"
experimental="false"
debugfb="false"
showfritzindexes="false"

checksettings
readconfig
checksettings ${configfile}

commandlist="^(\
add|del|(en|dis)able|show|\
extip(v[46])?|connstat|ddnsinfo|wlancount|\
(autowol|dect|deflections|device|homeauto|homeplug|hosts|storage|tam|tr69|update|upnpmedia|wlan[123])info|\
(autowol|ftp|ftpwan|ftpwanssl|homeauto|media|nas|smb|tam|upnp|wlan[123]?)switch|\
wolclient|tamcap|reconnect|reboot|savefbconfig|\
devicelog|\
listxmlfiles|showxmlfile|mysoaprequest|write(config|soapfile)|\
([-]{2})?version|\
([-]{2})?help|[-]h\
)$"

experimentallist="^(homeauto|tam|wlan[123]?)switch$"

switchlist="^(autowol|ftp|ftpwan|ftpwanssl|homeauto|media|nas|smb|tam|upnp|wlan[123])switch$"

# parse commands
if [ -z "${1}" ] || ! (echo "${1}" | grep -Eq "${commandlist}")
then
    if [ -n "${1}" ]
    then
        mecho --error "Wrong command \"${1}\" given"
    else
        mecho --error "No command given"
    fi
    usage commandline
    exit_code=4
    remove_debugfbfile
    exit 4
else
    command="${1}"
    shift
    if [ "${command}" = "help" ] || [ "${command}" = "--help" ] || [ "${command}" = "-h" ] ||
       [ "${command}" = "version" ] || [ "${command}" = "--version" ]
    then
        if [ "${command}" = "help" ] || [ "${command}" = "--help" ] || [ "${command}" = "-h" ]
        then
            usage fullhelp
        else
            usage version
        fi
        exit
    else
        if [ "${command}" = "writeconfig" ] || [ "${command}" = "writesoapfile" ]
        then
            if [ "${command}" = "writesoapfile" ]
            then
                if [ -n "${1}" ]
                then
                    soapfile="${1}"
                    if [ "${soapfile:0:1}" != "/" ]
                    then
                        mecho --error "File ${soapfile} has to be given with full path!"
                        usage commandline
                        exit_code=6
                        remove_debugfbfile
                        exit 6
                    fi
                fi
            fi
            if [ -n "${configfile}" ] || [ -n "${soapfile}" ]
            then
                ${command}
                exit
            else
                if [ "${command}" = "writesoapfile" ]
                then
                    mecho --error "Command \"${command}\" aborted because \${HOME} is not set and target file not given!"
                else
                    mecho --error "Command \"${command}\" aborted because \${HOME} is not set!"
                fi
                exit_code=13
                remove_debugfbfile
                exit 13
            fi
        else
            if (echo "${command}" | grep -Eq "${switchlist}")
            then
                if ! (echo "${*}" | grep -q "\-\-active" || echo "${*}" | grep -q "\-\-inactive")
                then
                    mecho --error "Necessary option \"--active\" or \"--inactive\" for command \"${command}\" not given"
                    usage commandline
                    exit_code=6
                    remove_debugfbfile
                    exit 6
                fi
            fi
            if [ "${command}" = "mysoaprequest" ]
            then
                if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
                then
                    if [ -f "${1}" ]
                    then
                        mysoaprequestfile="${1}"
                        if [ "${mysoaprequestfile:0:1}" != "/" ]
                        then
                            . "./${mysoaprequestfile}"
                        else
                            . "${mysoaprequestfile}"
                        fi
                        checksettings "${mysoaprequestfile}"
                        shift
                    else
                        mecho --error "File ${1} not found for command \"${command}\""
                        usage commandline
                        exit_code=12
                        remove_debugfbfile
                        exit 12
                    fi
                fi
            else
                if [ "${command}" = "autowolswitch" ] || [ "${command}" = "autowolinfo" ] || [ "${command}" = "wolclient" ]
                then
                    if [ -n "${1}" ] && (echo "${1}" | grep -Eq "^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$")
                    then
                        mac="${1}"
                        shift
                    else
                        mecho --error "Wrong or no value for mac address given"
                        usage commandline
                        exit_code=6
                        remove_debugfbfile
                        exit 6
                    fi
                else
                    if [ "${command}" = "homeautoswitch" ]
                    then
                        if [ -n "${1}" ] && (echo "${1}" | grep -Eq "^[0-9a-xA-X:-\ ]+$")
                        then
                            ain="${1}"
                            shift
                        else
                            mecho --error "Wrong or no value for ain given"
                            usage commandline
                            exit_code=6
                            remove_debugfbfile
                            exit 6
                        fi
                    else
                        if [ "${command}" = "tamswitch" ]
                        then
                            if [ -n "${1}" ] && (echo "${1}" | grep -Eq "^[0-9]{1}$")
                            then
                                tamindex="${1}"
                                shift
                            else
                                mecho --error "Wrong or no value for index given"
                                usage commandline
                                exit_code=6
                                remove_debugfbfile
                                exit 6
                            fi
                        else
                            if [ "${command}" = "showxmlfile" ]
                            then
                                if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
                                then
                                    descfile="${1}"
                                    shift
                                else
                                    descfile="tr64desc.xml"
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi
fi

# parse optional parameters
while [ -n "${1}" ]
do
    case "${1}"
    in
        --fbip)
            shift
            if (echo "${1}" | grep -Eq "^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])){3}$") ||
               (echo "${1}" | grep -Eq "^[[:alnum:]]([-]*[[:alnum:]])*(\.[[:alnum:]]([-]*[[:alnum:]])*)*$")
            then
                FBIP="${1}"
                shift
            else
                mecho --error "Wrong or no value for fritzbox address given"
                usage commandline
                exit_code=6
                remove_debugfbfile
                exit 6
            fi
        ;;
        --description)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                new_port_mapping_description="${1}"
                shift
            else
                mecho --error "No description given"
                usage commandline
                exit_code=6
                remove_debugfbfile
                exit 6
            fi
        ;;
        --extport)
            shift
            if  (echo "${1}" | grep -Eq "^[[:digit:]]{1,5}$") && [ "${1}" -ge 0 ] && [ "${1}" -le 65535 ]
            then
                new_external_port="${1}"
                shift
            else
                mecho --error "Wrong or no value for external port given"
                usage commandline
                exit_code=6
                remove_debugfbfile
                exit 6
            fi
        ;;
        --intclient)
            shift
            if (echo "${1}" | grep -Eq "^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])){3}$")
            then
                new_internal_client="${1}"
                shift
            else
                mecho --error "Wrong or no value for internal client ip address given"
                usage commandline
                exit_code=6
                remove_debugfbfile
                exit 6
            fi
        ;;
        --intport)
            shift
            if (echo "${1}" | grep -Eq "^[[:digit:]]{1,5}$") && [ "${1}" -ge 0 ]  && [ "${1}" -le 65535 ]
            then
                new_internal_port="${1}"
                shift
            else
                mecho --error "Wrong or no value for internal client port given"
                usage commandline
                exit_code=6
                remove_debugfbfile
                exit 6
            fi
        ;;
        --protocol)
            shift
            new_protocol=$(echo "${1}" | tr [:lower:] [:upper:])
            shift
            if [ "${new_protocol}" != "TCP" ] && [ "${new_protocol}" != "UDP" ]
            then
                mecho --error "Wrong or no value for protocol given"
                usage commandline
                exit_code=6
                remove_debugfbfile
                exit 6
            fi
        ;;
        --active)
            new_enabled="1"
            shift
        ;;
        --inactive)
            new_enabled="0"
            shift
        ;;
        --searchhomeautoain)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                searchhomeautoain="${1}"
                shift
            else
                searchhomeautoain=""
            fi
        ;;
        --searchhomeautodeviceid)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                searchhomeautodeviceid="${1}"
                shift
            else
                searchhomeautodeviceid=""
            fi
        ;;
        --searchhomeautodevicename)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                searchhomeautodevicename="${1}"
                shift
            else
                searchhomeautodevicename=""
            fi
        ;;
        --fbconffilepath)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ] && [ -d "${1}" ]
            then
                fbconffilepath="${1}"
                shift
            else
                mecho --error "No or unavailable path given"
                usage commandline
                exit_code=6
                remove_debugfbfile
                exit 6
            fi
        ;;
        --fbconffileprefix)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                fbconffileprefix="${1}"
                shift
            else
                fbconffileprefix=""
            fi
        ;;
        --fbconffilesuffix)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                fbconffilesuffix="${1}"
                shift
            else
                fbconffilesuffix=""
            fi
        ;;
        --fbconffilepassword)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                fbconffilepassword="${1}"
                shift
            else
                fbconffilepassword=""
            fi
        ;;
        --ftpwanon)
            ftpwanon="1"
            shift
        ;;
        --ftpwanoff)
            ftpwanon="0"
            shift
        ;;
        --ftpwansslonlyon)
            ftpwansslonlyon="1"
            shift
        ;;
        --ftpwansslonlyoff)
            ftpwansslonlyon="0"
            shift
        ;;
        --mediaon)
            mediaon="1"
            shift
        ;;
        --mediaoff)
            mediaon="0"
            shift
        ;;
        --upnpon)
            upnpon="1"
            shift
        ;;
        --upnpoff)
            upnpon="0"
            shift
        ;;
        --showfritzindexes)
            showfritzindexes="true"
            shift
        ;;
        --rawdevicelog)
            rawdevicelog="1"
            shift
        ;;
        --soapfilter)
            soapfilter="1"
            shift
        ;;
        --SOAPtype)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                type="${1}"
                shift
            else
                type=""
            fi
        ;;
        --SOAPdescfile)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                descfile="${1}"
                shift
            else
                descfile=""
            fi
        ;;
        --SOAPcontrolURL)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                controlURL="${1}"
                shift
            else
                controlURL=""
            fi
        ;;
        --SOAPserviceType)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                serviceType="${1}"
                shift
            else
                serviceType=""
            fi
        ;;
        --SOAPaction)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                action="${1}"
                shift
            else
                action=""
            fi
        ;;
        --SOAPdata)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                data="${1}"
                shift
            else
                data=""
            fi
        ;;
        --SOAPsearch)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                search="${1}"
                shift
            else
                search=""
            fi
        ;;
        --SOAPtitle)
            shift
            if [ -n "${1}" ] && [ "${1:0:2}" != "--" ]
            then
                title="${1}"
                shift
            else
                title=""
            fi
        ;;
        --experimental)
            experimental="true"
            shift
        ;;
        --debugfb)
            debugfb="true"
            debugfbfile="/tmp/avm-fritz-toolbox.sh."$(mktemp -u XXXXXXXX)
            shift
        ;;
        -h|--help)
            shift
        ;;
        *)
            mecho --error "Wrong option \"${1}\" given"
            usage commandline
            exit_code=5
            remove_debugfbfile
            exit 5
        ;;
    esac
done

# Exit if experimental switch is not given on experimental commands
if [ "${experimental:-false}" = "false" ] && (echo "${command}" | grep -Eq "${experimentallist}")
then
    mecho --error "Function \"${command}\" only available in experimental mode; Add --experimental switch to command line"
    exit_code=11
    remove_debugfbfile
    exit 11
fi

determineauthmethod

CURL_BIN=$(which curl 2>/dev/null)

if [ -x "${CURL_BIN}" ]
then
    # curl binary exists, go on...

    exit_code=0

    # check if host is reachable
    ping -c 3 ${FBIP} >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
        wget -t 1 --spider ${FBIP} >/dev/null 2>&1
    fi
    if [ $? -eq 0 ]
    then
        # host is reachable, go on...
        # read control URL and urn from description
        get_url_and_urn "tr64desc.xml" "deviceinfo" "DeviceInfo:1"
        # read security port
        FBPORTSSL=$(execute_http_soap_request \
            "GetSecurityPort" \
            "")
        FBPORTSSL=$(parse_xml_response "${FBPORTSSL}" "NewSecurityPort")
        # FBPORTSSL=$(echo "${FBPORTSSL}" | grep "NewSecurityPort" | sed 's#^.*<NewSecurityPort>\(.*\)<.*$#\1#')
        if [ "${debugfb:-false}" = "true" ]
        then
            (
                echo
                echo "fbsslport: ${FBPORTSSL}"
            ) >> ${debugfbfile}
        fi
        if [ "${FBPORTSSL}" = "" ]
        then
            mecho --error "Unable to get security port"
            exit_code=1
            output_debugfbfile
            exit 1
        fi

        # read fritzbox description
        # read control URL and urn from description
        get_url_and_urn "tr64desc.xml" "deviceinfo" "DeviceInfo:1"
        deviceinfo=$(execute_https_soap_request \
            "GetInfo" \
            "")
        if (echo "${deviceinfo}" | grep -q "GetInfoResponse")
        then
            device="("$(parse_xml_response "${deviceinfo}" "NewDescription")"@${FBIP})"
            if [ "${debugfb:-false}" = "true" ]
            then
                debugdevice=$(parse_xml_response "${deviceinfo}" "NewDescription")"@${FBIP}"
            fi
        fi
        if [ "${device}" = "" ]
        then
            mecho --error "Unable to get device name"
            exit_code=1
            output_debugfbfile
            exit 1
        fi

        # detect wan connection type (IP or PPP)
        # read control URL and urn from description
        get_url_and_urn "tr64desc.xml" "wanpppconn1" "WANPPPConnection:1"
        # ppp connection?
        FBCONNTYPE="IP"
        (execute_https_soap_request \
            "GetInfo" \
            "" \
            | grep  -q "GetInfoResponse") && FBCONNTYPE="PPP"

        case "${command}"
        in
            add|enable|disable)
                # add, enable or disable port forward
                # read control URL and urn from description
                if [ "${FBCONNTYPE:-IP}" = "PPP" ]
                then
                    get_url_and_urn "tr64desc.xml" "wanpppconn1" "WANPPPConnection:1"
                else
                    get_url_and_urn "tr64desc.xml" "wanipconnection1" "WANIPConnection:1"
                fi
                [ ${command} = "enable" ] && new_enabled="1"
                [ ${command} = "disable" ] && new_enabled="0"
                # clear currently unused variables
                new_remote_host=""
                new_lease_duration="0"
                execute_https_soap_request \
                    "AddPortMapping" \
                    "<NewRemoteHost>${new_remote_host}</NewRemoteHost>
                     <NewExternalPort>${new_external_port}</NewExternalPort>
                     <NewProtocol>${new_protocol}</NewProtocol>
                     <NewInternalPort>${new_internal_port}</NewInternalPort>
                     <NewInternalClient>${new_internal_client}</NewInternalClient>
                     <NewEnabled>${new_enabled}</NewEnabled>
                     <NewPortMappingDescription>${new_port_mapping_description}</NewPortMappingDescription>
                     <NewLeaseDuration>${new_lease_duration}</NewLeaseDuration>" \
                    | grep -q "AddPortMappingResponse"
                    exit_code=$?
            ;;
            del)
                # delete port forward
                # read control URL and urn from description
                if [ "${FBCONNTYPE:-IP}" = "PPP" ]
                then
                    get_url_and_urn "tr64desc.xml" "wanpppconn1" "WANPPPConnection:1"
                else
                    get_url_and_urn "tr64desc.xml" "wanipconnection1" "WANIPConnection:1"
                fi
                # clear currently unused variable
                new_remote_host=""
                execute_https_soap_request \
                    "DeletePortMapping" \
                    "<NewRemoteHost>${new_remote_host}</NewRemoteHost>
                     <NewExternalPort>${new_external_port}</NewExternalPort>
                     <NewProtocol>${new_protocol}</NewProtocol>" \
                    | grep -Eq "DeletePortMappingResponse|NoSuchEntryInArray"
                exit_code=$?
            ;;
            show)
                # show port forwardings
                # normal port forwardings set by authorized user
                mecho --info "Port forwardings ${device}"
                mecho --info "Port forwardings set by authorized users"
                # read control URL and urn from description
                if [ "${FBCONNTYPE:-IP}" = "PPP" ]
                then
                    get_url_and_urn "tr64desc.xml" "wanpppconn1" "WANPPPConnection:1"
                else
                    get_url_and_urn "tr64desc.xml" "wanipconnection1" "WANIPConnection:1"
                fi
                idx=0
                portmappingcount=$(execute_https_soap_request \
                    "GetPortMappingNumberOfEntries" \
                    "")
                portmappingcount=$(parse_xml_response "${portmappingcount}" "NewPortMappingNumberOfEntries")
                if [ -n "${portmappingcount}" ] && [ "${portmappingcount}" -gt 0 ]
                then
                    techo --begin "4r 4 26 17 4 25"
                    techo --info --row "Idx" "Act" "Description" "Host IP:Port" "Pro" "Client IP:Port"
                    while [ "${idx}" -lt "${portmappingcount}" ]
                    do
                        if [ "${showfritzindexes:-false}" = "true" ]
                        then
                            count="${idx}"
                        else
                            count=$(expr ${idx} + 1)
                        fi
                        portmappingentry=$(execute_https_soap_request \
                            "GetGenericPortMappingEntry" \
                            "<NewPortMappingIndex>${idx}</NewPortMappingIndex>")
                        if (echo "${portmappingentry}" | grep -q "SpecifiedArrayIndexInvalid")
                        then
                            mecho --error "Invalid port forwarding index found."
                            mecho --error "Please reboot your Fritzbox to fix the problem."
                            exit_code=1
                            break
                        else
                            portmappingenabled=$(parse_xml_response "${portmappingentry}" "NewEnabled")
                            portmappingdescription=$(parse_xml_response "${portmappingentry}" "NewPortMappingDescription")
                            portmappingremotehost=$(parse_xml_response "${portmappingentry}" "NewRemoteHost")
                            # maybe faulty in fritzbox; have to reverse parameters
                            if [ "${FBREVERSEPORTS}" = "true" ]
                            then
                                portmappingremoteport=$(parse_xml_response "${portmappingentry}" "NewInternalPort")
                                portmappinginternalport=$(parse_xml_response "${portmappingentry}" "NewExternalPort")
                            else
                                portmappingremoteport=$(parse_xml_response "${portmappingentry}" "NewExternalPort")
                                portmappinginternalport=$(parse_xml_response "${portmappingentry}" "NewInternalPort")
                            fi
                            portmappingprotocol=$(parse_xml_response "${portmappingentry}" "NewProtocol")
                            portmappinginternalclient=$(parse_xml_response "${portmappingentry}" "NewInternalClient")
                            portmappingleaseduration=$(parse_xml_response "${portmappingentry}" "NewLeaseDuration")
                            techo --row \
                                "${count}" \
                                "$(convert_yes_no ${portmappingenabled})" \
                                "${portmappingdescription}" \
                                "${portmappingremotehost}:${portmappingremoteport}" \
                                "${portmappingprotocol}" \
                                "${portmappinginternalclient}:${portmappinginternalport}"
                            idx=$(expr ${idx} + 1)
                        fi
                    done
                    techo --end
                else
                    [ -z "${portmappingcount}" ] && exit_code=1
                fi
                # port forwardings set by any user via upnp if allowed under "Internet|Freigaben|Portfreigaben"
                echo
                mecho --info "Port forwardings set by any user/device via upnp"
                # read control URL and urn from description
                get_url_and_urn "igddesc.xml" "WANIPConn1" "WANIPConnection:1"
                idx=0
                while [ true ]
                do
                    if [ "${showfritzindexes:-false}" = "true" ]
                    then
                        count="${idx}"
                    else
                        count=$(expr ${idx} + 1)
                    fi
                    portmappingentry=$(execute_https_soap_request \
                        "GetGenericPortMappingEntry" \
                        "<NewPortMappingIndex>${idx}</NewPortMappingIndex>")
                    if (echo "${portmappingentry}" | grep -q "Invalid Action")
                    then
                        mecho --warn "UPnP not activated in network settings, change in webgui or execute"
                        mecho --warn "\"$(basename ${0}) upnpmediaswitch --active\""
                        mecho --warn "if you want to see port forwardings set by any user/device."
                        exit_code=1
                        output_debugfbfile
                        exit 1
                    fi
                    # if ! (echo "${portmappingentry}" | grep -q "SpecifiedArrayIndexInvalid") &&
                    if (echo "${portmappingentry}" | grep -q "GetGenericPortMappingEntryResponse")
                    then
                        portmappingenabled=$(parse_xml_response "${portmappingentry}" "NewEnabled")
                        portmappingdescription=$(parse_xml_response "${portmappingentry}" "NewPortMappingDescription")
                        portmappingremotehost=$(parse_xml_response "${portmappingentry}" "NewRemoteHost")
                        if [ -z "${portmappingremotehost}" ]
                        then
                            portmappingremotehost="0.0.0.0"
                        fi
                        portmappingremoteport=$(parse_xml_response "${portmappingentry}" "NewExternalPort")
                        portmappingprotocol=$(parse_xml_response "${portmappingentry}" "NewProtocol")
                        portmappinginternalclient=$(parse_xml_response "${portmappingentry}" "NewInternalClient")
                        portmappinginternalport=$(parse_xml_response "${portmappingentry}" "NewInternalPort")
                        portmappingleaseduration=$(parse_xml_response "${portmappingentry}" "NewLeaseDuration")
                        if [ "${idx}" -eq 0 ]
                        then
                            techo --begin "4r 4 26 17 4 25"
                            techo --info --row "Idx" "Act" "Description" "Host IP:Port" "Pro" "Client IP:Port"
                        fi
                        techo --row \
                            "${count}" \
                            "$(convert_yes_no ${portmappingenabled})" \
                            "${portmappingdescription}" \
                            "${portmappingremotehost}:${portmappingremoteport}" \
                            "${portmappingprotocol}" \
                            "${portmappinginternalclient}:${portmappinginternalport}"
                        idx=$(expr ${idx} + 1)
                    else
                        if [ "${idx}" -gt 0 ]
                        then
                            techo --end
                        fi
                        break
                    fi
                done
            ;;
            extip)
                # print external ipv4 address
                # read control URL and urn from description
                if [ "${FBCONNTYPE:-IP}" = "PPP" ]
                then
                    get_url_and_urn "tr64desc.xml" "wanpppconn1" "WANPPPConnection:1"
                else
                    get_url_and_urn "tr64desc.xml" "wanipconnection1" "WANIPConnection:1"
                fi
                extipv4address=$(execute_https_soap_request \
                    "GetExternalIPAddress" \
                    "")
                extipv4address=$(parse_xml_response "${extipv4address}" "NewExternalIPAddress")
                mecho --info "External IPv4/v6 data ${device}"
                if [ -n "${extipv4address}" ]
                then
                    mecho --info "External IPv4 address: ${extipv4address}"
                else
                    mecho -n --info "External IPv4 address: "
                    mecho --error "No external IPv4 address"
                    exit_code=9
                fi
                # print external ipv6 address
                # read control URL and urn from description
                get_url_and_urn "igddesc.xml" "WANIPConn1" "WANIPConnection:1"
                extipv6address=$(execute_https_soap_request \
                    "X_AVM_DE_GetExternalIPv6Address" \
                    "")
                extipv6address=$(parse_xml_response "${extipv6address}" "NewExternalIPv6Address")
                if [ -n "${extipv6address}" ]
                then
                    mecho --info "External IPv6 address: ${extipv6address}"
                    extipv6prefix=$(execute_https_soap_request \
                        "X_AVM_DE_GetIPv6Prefix" \
                        "")
                    extipv6prefix=$(parse_xml_response "${extipv6prefix}" "NewIPv6Prefix")
                    if [ -n "${extipv6prefix}" ]
                    then
                        mecho --info "External IPv6 prefix : ${extipv6prefix}"
                    else
                        mecho -n --info "External IPv6 prefix : "
                        mecho --error "No external IPv6 prefix"
                        exit_code=10
                    fi
                else
                    mecho -n --info "External IPv6 address: "
                    mecho --error "No external IPv6 address"
                    exit_code=10
                fi
            ;;
            extipv4)
                # print external ipv4 address
                # read control URL and urn from description
                if [ "${FBCONNTYPE:-IP}" = "PPP" ]
                then
                    get_url_and_urn "tr64desc.xml" "wanpppconn1" "WANPPPConnection:1"
                else
                    get_url_and_urn "tr64desc.xml" "wanipconnection1" "WANIPConnection:1"
                fi
                extipv4address=$(execute_https_soap_request \
                    "GetExternalIPAddress" \
                    "")
                extipv4address=$(parse_xml_response "${extipv4address}" "NewExternalIPAddress")
                if [ -n "${extipv4address}" ]
                then
                    mecho --info "External IPv4 address ${device}: ${extipv4address}"
                else
                    mecho -n --info "External IPv4 address: "
                    mecho --error "No external IPv4 address"
                    exit_code=9
                fi
            ;;
            extipv6)
                # print external ipv6 address
                # read control URL and urn from description
                get_url_and_urn "igddesc.xml" "WANIPConn1" "WANIPConnection:1"
                extipv6address=$(execute_https_soap_request \
                    "X_AVM_DE_GetExternalIPv6Address" \
                    "")
                mecho --info "External IPv6 data ${device}"
                extipv6address=$(parse_xml_response "${extipv6address}" "NewExternalIPv6Address")
                if [ -n "${extipv6address}" ]
                then
                    mecho --info "External IPv6 address: ${extipv6address}"
                    extipv6prefix=$(execute_https_soap_request \
                        "X_AVM_DE_GetIPv6Prefix" \
                        "")
                    extipv6prefix=$(parse_xml_response "${extipv6prefix}" "NewIPv6Prefix")
                    if [ -n "${extipv6prefix}" ]
                    then
                        mecho --info "External IPv6 prefix : ${extipv6prefix}"
                    else
                        mecho -n --info "External IPv6 prefix : "
                        mecho --error "No external IPv6 prefix"
                        exit_code=10
                    fi
                else
                    mecho -n --info "External IPv6 address: "
                    mecho --error "No external IPv6 address"
                    exit_code=10
                fi
            ;;
            connstat)
                # internet connection status
                # read control URL and urn from description
                if [ "${FBCONNTYPE:-IP}" = "PPP" ]
                then
                    get_url_and_urn "tr64desc.xml" "wanpppconn1" "WANPPPConnection:1"
                else
                    get_url_and_urn "tr64desc.xml" "wanipconnection1" "WANIPConnection:1"
                fi
                execute_https_soap_request \
                    "GetStatusInfo" \
                    "" \
                    | grep -q "Connected"
                exit_code=$?
                if [ "${exit_code}" -eq 0 ]
                then
                    mecho --info "Internet connection established ${device}"
                else
                    exit_code=8
                fi
            ;;
            ddnsinfo)
                # ddns service informations
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_remote" "X_AVM-DE_RemoteAccess:1"
                ddnsinfo=$(execute_https_soap_request \
                    "GetDDNSInfo" \
                    "")
                if (echo "${ddnsinfo}" | grep -q "GetDDNSInfoResponse")
                then
                    ddnsinfoenabled=$(parse_xml_response "${ddnsinfo}" "NewEnabled")
                    ddnsinfoprovider=$(parse_xml_response "${ddnsinfo}" "NewProviderName")
                    # ddnsinfoupdateurl=$(parse_xml_response "${ddnsinfo}" "NewUpdateURL" | sed 's#\&lt;#<#g' | sed 's#\&gt;#>#g' | sed 's#\&amp;#\&#g')
                    ddnsinfoupdateurl=$(parse_xml_response "${ddnsinfo}" "NewUpdateURL")
                    ddnsinfoupdateurl=$(convert_html_entities "${ddnsinfoupdateurl}")
                    ddnsinfodomain=$(parse_xml_response "${ddnsinfo}" "NewDomain")
                    ddnsinfostatusipv4=$(parse_xml_response "${ddnsinfo}" "NewStatusIPv4")
                    ddnsinfostatusipv6=$(parse_xml_response "${ddnsinfo}" "NewStatusIPv6")
                    ddnsinfousername=$(parse_xml_response "${ddnsinfo}" "NewUsername")
                    ddnsinfomode=$(parse_xml_response "${ddnsinfo}" "NewMode")
                    ddnsinfoserveripv4=$(parse_xml_response "${ddnsinfo}" "NewServerIPv4")
                    ddnsinfoserveripv6=$(parse_xml_response "${ddnsinfo}" "NewServerIPv6")
                    mecho --info "Dynamic DNS service informations ${device}"
                    echo "Enabled       : $(convert_yes_no ${ddnsinfoenabled})"
                    echo "Provider name : ${ddnsinfoprovider}"
                    echo "Update URL    : ${ddnsinfoupdateurl}"
                    echo "Domain        : ${ddnsinfodomain}"
                    echo "User name     : ${ddnsinfousername}"
                    case "${ddnsinfomode}"
                    in
                        ddns_v4)
                            echo "Update mode   : Update only IPv4 address"
                        ;;
                        ddns_v6)
                            echo "Update mode   : Update only IPv6 address"
                        ;;
                        ddns_both)
                            echo "Update mode   : Update IPv4 and IPv6 addresses with separate requests"
                        ;;
                        ddns_both_together)
                            echo "Update mode   : Update IPv4 and IPv6 addresses with one request"
                        ;;
                    esac
                    echo "Status IPv4   : ${ddnsinfostatusipv4}"
                    echo "Status IPv6   : ${ddnsinfostatusipv6}"
                    echo "Server IPv4   : ${ddnsinfoserveripv4}"
                    echo "Server IPv6   : ${ddnsinfoserveripv6}"
                else
                    exit_code=1
                fi
            ;;
            wlancount)
                # determine number and type of wlans
                wlancount=$(${CURL_BIN} -s "http://${FBIP}:${FBPORT}/tr64desc.xml" | grep -Eo "WLANConfiguration:"'[[:digit:]]{1}'"</serviceType>" | wc -l)
                mecho --info "Number and type of WLANs ${device}"
                mecho --info "(use number for wlan<n>info and wlan<n>switch commands)"
                case "${wlancount}"
                in
                    0)
                        echo "No WLAN available"
                    ;;
                    1)
                        mecho -n --warn "1"
                        mecho --std ": 2,4 GHz WLAN available"
                    ;;
                    2)
                        mecho -n --warn "1" 
                        mecho --std ": 2,4 GHz WLAN available"
                        mecho -n --warn "2"
                        mecho --std ": Guest WLAN available"
                    ;;
                    3)
                        mecho -n --warn "1"
                        mecho  --std ": 2,4 GHz WLAN available"
                        mecho -n --warn "2"
                        mecho --std ": 5 GHz WLAN available"
                        mecho -n --warn "3"
                        mecho --std ": Guest WLAN available"
                    ;;
                    *)
                        mecho --error "${wlancount} WLANs of unknown type"
                        exit_code=1
                    ;;
                esac
            ;;
            wlanswitch)
                # wlan enable/disable switch; acts as button on fritzbox does
                get_url_and_urn "tr64desc.xml" "wlanconfig1" "WLANConfiguration:1"
                execute_https_soap_request \
                    "X_AVM-DE_SetWLANGlobalEnable" \
                    "<NewX_AVM-DE_WLANGlobalEnable>${new_enabled}</NewX_AVM-DE_WLANGlobalEnable>" \
                    | grep -q "X_AVM-DE_SetWLANGlobalEnableResponse"
                exit_code=$?
            ;;
            wlan1switch|wlan2switch|wlan3switch)
                # wlan1/wlan2/wlan3 (2,4 GHz/5 GHz or guest/guest) enable/disable switch
                # determine count of wlans
                wlancount=$(${CURL_BIN} -s "http://${FBIP}:${FBPORT}/tr64desc.xml" | grep -Eo "WLANConfiguration:"'[[:digit:]]{1}'"</serviceType>" | wc -l)
                case "${command}"
                in
                    wlan1switch)
                        if [ "${wlancount}" -gt 0 ]
                        then
                            # read control URL and urn from description
                            get_url_and_urn "tr64desc.xml" "wlanconfig1" "WLANConfiguration:1"
                        else
                            mecho --warn "No WLAN available ${device}"
                            exit_code=1
                            output_debugfbfile
                            exit 1
                        fi
                    ;;
                    wlan2switch)
                        if [ "${wlancount}" -gt 1 ]
                        then
                            # read control URL and urn from description
                            get_url_and_urn "tr64desc.xml" "wlanconfig2" "WLANConfiguration:2"
                        else
                            mecho --warn "Fritzbox has no second wlan ${device}"
                            exit_code=1
                            output_debugfbfile
                            exit 1
                        fi
                    ;;
                    wlan3switch)
                        if [ "${wlancount}" -gt 2 ]
                        then
                            # read control URL and urn from description
                            get_url_and_urn "tr64desc.xml" "wlanconfig3" "WLANConfiguration:3"
                        else
                            mecho --warn "Fritzbox has no third wlan ${device}"
                            exit_code=1
                            output_debugfbfile
                            exit 1
                        fi
                    ;;
                esac
                execute_https_soap_request \
                    "SetEnable" \
                    "<NewEnable>${new_enabled}</NewEnable>" \
                    | grep -q "SetEnableResponse"
                exit_code=$?
            ;;
            wlan1info|wlan2info|wlan3info)
                # wlan1 (2,4 GHz, 5 Ghz, guest wlan) informations
                # determine count of wlans
                wlancount=$(${CURL_BIN} -s "http://${FBIP}:${FBPORT}/tr64desc.xml" | grep -Eo "WLANConfiguration:"'[[:digit:]]{1}'"</serviceType>" | wc -l)
                wlan1text="WLAN (2,4 GHz) informations ${device}"
                if [ "${wlancount}" -eq 2 ]
                then
                    wlan2text="Guest WLAN informations ${device}"
                else
                    wlan2text="WLAN (5 GHz) informations ${device}"
                fi
                wlan3text="Guest WLAN informations ${device}"
                case "${command}"
                in
                    wlan1info)
                        if [ "${wlancount}" -gt 0 ]
                        then
                            # read control URL and urn from description
                            get_url_and_urn "tr64desc.xml" "wlanconfig1" "WLANConfiguration:1"
                        else
                            mecho --warn "No WLAN available ${device}"
                            exit_code=1
                            output_debugfbfile
                            exit 1
                        fi
                    ;;
                    wlan2info)
                        if [ "${wlancount}" -gt 1 ]
                        then
                            # read control URL and urn from description
                            get_url_and_urn "tr64desc.xml" "wlanconfig2" "WLANConfiguration:2"
                        else
                            mecho --warn "Fritzbox has no second wlan ${device}"
                            exit_code=1
                            output_debugfbfile
                            exit 1
                        fi
                    ;;
                    wlan3info)
                        if [ "${wlancount}" -gt 2 ]
                        then
                            # read control URL and urn from description
                            get_url_and_urn "tr64desc.xml" "wlanconfig3" "WLANConfiguration:3"
                        else
                            mecho --warn "Fritzbox has no third wlan ${device}"
                            exit_code=1
                            output_debugfbfile
                            exit 1
                        fi
                    ;;
                esac
                wlaninfo=$(execute_https_soap_request \
                    "GetInfo" \
                    "")
                if (echo "${wlaninfo}" | grep -q "GetInfoResponse")
                then
                    wlaninfoenabled=$(parse_xml_response "${wlaninfo}" "NewEnable")
                    wlaninfostatus=$(parse_xml_response "${wlaninfo}" "NewStatus")
                    wlaninfomaxbitrate=$(parse_xml_response "${wlaninfo}" "NewMaxBitRate")
                    wlaninfochannel=$(parse_xml_response "${wlaninfo}" "NewChannel")
                    wlaninfossid=$(parse_xml_response "${wlaninfo}" "NewSSID")
                    wlaninfobeacon=$(parse_xml_response "${wlaninfo}" "NewBeaconType")
                    wlaninfomaccontrol=$(parse_xml_response "${wlaninfo}" "NewMACAddressControlEnabled")
                    wlaninfostandard=$(parse_xml_response "${wlaninfo}" "NewStandard")
                    wlaninfobssid=$(parse_xml_response "${wlaninfo}" "NewBSSID")
                    wlaninfobasicencryp=$(parse_xml_response "${wlaninfo}" "NewBasicEncryptionModes")
                    wlaninfobasicauth=$(parse_xml_response "${wlaninfo}" "NewBasicAuthenticationMode")
                    wlaninfomaxcharsssid=$(parse_xml_response "${wlaninfo}" "NewMaxCharsSSID")
                    wlaninfomincharsssid=$(parse_xml_response "${wlaninfo}" "NewMinCharsSSID")
                    wlaninfoallowedcharsssid=$(parse_xml_response "${wlaninfo}" "NewAllowedCharsSSID")
                    wlaninfoallowedcharsssid1=$(echo "${wlaninfoallowedcharsssid}" | cut -d " " -f 1)
                    # wlaninfoallowedcharsssid2=$(echo "${wlaninfoallowedcharsssid}" | cut -d "z" -f 2 | sed 's#\&lt;#<#g' | sed 's#\&gt;#>#g' | sed 's#\&amp;#\&#g' | sed 's#\&quot;#"#g' | sed "s#\&apos;#'#g")
                    wlaninfoallowedcharsssid2=$(echo "${wlaninfoallowedcharsssid}" | cut -d "z" -f 2)
                    wlaninfoallowedcharsssid2=$(convert_html_entities "${wlaninfoallowedcharsssid2}")
                    wlaninfomaxcharspsk=$(parse_xml_response "${wlaninfo}" "NewMaxCharsPSK")
                    wlaninfomincharspsk=$(parse_xml_response "${wlaninfo}" "NewMinCharsPSK")
                    wlaninfoallowedcharspsk=$(parse_xml_response "${wlaninfo}" "NewAllowedCharsPSK")
                    case "${command}" in
                        wlan1info)
                            mecho --info "${wlan1text}"
                        ;;
                        wlan2info)
                            mecho --info "${wlan2text}"
                        ;;
                        wlan3info)
                            mecho --info "${wlan3text}"
                        ;;
                    esac
                    echo "Enabled                   : $(convert_yes_no ${wlaninfoenabled})"
                    echo "Status                    : ${wlaninfostatus}"
                    # Currently not supported
                    # echo "Max Bit Rate              : ${wlaninfomaxbitrate}"
                    echo "Channel                   : ${wlaninfochannel}"
                    echo "SSID                      : ${wlaninfossid}"
                    echo "Beacon Type               : ${wlaninfobeacon}"
                    echo "MAC Address Control       : $(convert_yes_no ${wlaninfomaccontrol})"
                    # Currently not supported
                    # echo "Standard                  : ${wlaninfostandard}"
                    echo "BSSID                     : ${wlaninfobssid}"
                    echo "Basic Encryption Modes    : ${wlaninfobasicencryp}"
                    # Currently not supported
                    # echo "Basic Authentication Mode : ${wlaninfobasicauth}"
                    echo "Max Chars SSID            : ${wlaninfomaxcharsssid}"
                    echo "Min Chars SSID            : ${wlaninfomincharsssid}"
                    echo "Allowed Chars SSID        : ${wlaninfoallowedcharsssid1}"
                    echo "                          : ${wlaninfoallowedcharsssid2}"
                    echo "Max Chars PSK             : ${wlaninfomaxcharspsk}"
                    echo "Min Chars PSK             : ${wlaninfomincharspsk}"
                    echo "Allowed Chars PSK         : ${wlaninfoallowedcharspsk}"
                else
                    exit_code=1
                fi
            ;;
            dectinfo)
                # show all dect telephones
                mecho --info "DECT telephone list ${device}"
                get_url_and_urn "tr64desc.xml" "x_dect" "X_AVM-DE_Dect:1"
                idx=0
                dectcount=$(execute_https_soap_request \
                    "GetNumberOfDectEntries" \
                    "")
                dectcount=$(parse_xml_response "${dectcount}" "NewNumberOfEntries")
                if [ -n "${dectcount}" ] && [ "${dectcount}" -gt 0 ]
                then
                    techo --begin "4r 4 19 19 10r 11 13"
                    techo --info --row "ID" "Act" "Name" "Model" "Upd:Avail" "Successfull" "Info"
                    while [ "${idx}" -lt "${dectcount}" ]
                    do
                        dectentry=$(execute_https_soap_request \
                            "GetGenericDectEntry" \
                            "<NewIndex>${idx}</NewIndex>")
                        if (echo "${dectentry}" | grep -q "GetGenericDectEntryResponse")
                        then
                            dectentryid=$(parse_xml_response "${dectentry}" "NewID")
                            dectentryactive=$(parse_xml_response "${dectentry}" "NewActive")
                            dectentryname=$(parse_xml_response "${dectentry}" "NewName")
                            dectentrymodel=$(parse_xml_response "${dectentry}" "NewModel")
                            dectentryupdateavailable=$(parse_xml_response "${dectentry}" "NewUpdateAvailable")
                            dectentryupdatesuccessful=$(parse_xml_response "${dectentry}" "NewUpdateSuccessful")
                            dectentryupdateinfo=$(parse_xml_response "${dectentry}" "NewUpdateInfo")
                            techo --row \
                                "${dectentryid}" \
                                "$(convert_yes_no ${dectentryactive})" \
                                "${dectentryname}" \
                                "${dectentrymodel}" \
                                "$(convert_yes_no ${dectentryupdateavailable})" \
                                "${dectentryupdatesuccessful}" \
                                "${dectentryupdateinfo}"
                            idx=$(expr ${idx} + 1)
                        else
                            mecho --error "Invalid dect index found."
                            mecho --error "Please reboot your Fritzbox to fix the problem."
                            exit_code=1
                            break
                        fi
                    done
                    techo --end
                else
                    [ -z "${dectcount}" ] && exit_code=1
                fi
            ;;
            deflectionsinfo)
                # show all telephone deflections
                mecho --info "Telephone deflections ${device}"
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_contact" "X_AVM-DE_OnTel:1"
                idx=0
                deflectionscount=$(execute_https_soap_request \
                    "GetNumberOfDeflections" \
                    "")
                deflectionscount=$(parse_xml_response "${deflectionscount}" "NewNumberOfDeflections")
                if [ -n "${deflectionscount}" ] && [ "${deflectionscount}" -gt 0 ]
                then
                    techo --begin "4r 4 13 15 34 4r 6r"
                    techo --info --row "Idx" "Act" "Type" "Mode" "Incoming > Outgoing number" "Out" "PB-ID"
                    while [ "${idx}" -lt "${deflectionscount}" ]
                    do
                        if [ "${showfritzindexes:-false}" = "true" ]
                        then
                            count="${idx}"
                        else
                            count=$(expr ${idx} + 1)
                        fi
                        deflection=$(execute_https_soap_request \
                            "GetDeflection" \
                            "<NewDeflectionID>${idx}</NewDeflectionID>")
                        if (echo "${deflection}" | grep -q "GetDeflectionResponse")
                        then
                            deflectionenabled=$(parse_xml_response "${deflection}" "NewEnable")
                            deflectiontype=$(parse_xml_response "${deflection}" "NewType")
                            deflectionnumber=$(parse_xml_response "${deflection}" "NewNumber")
                            deflectiontonumber=$(parse_xml_response "${deflection}" "NewDeflectionToNumber")
                            deflectionmode=$(parse_xml_response "${deflection}" "NewMode")
                            deflectionoutgoing=$(parse_xml_response "${deflection}" "NewOutgoing")
                            deflectionphonebookid=$(parse_xml_response "${deflection}" "NewPhonebookID")
                            techo --row \
                                "${count}" \
                                "$(convert_yes_no ${deflectionenabled})" \
                                "${deflectiontype}" \
                                "${deflectionmode}" \
                                "${deflectionnumber} > ${deflectiontonumber:--}" \
                                "${deflectionoutgoing}" \
                                "${deflectionphonebookid}"
                            idx=$(expr ${idx} + 1)
                        else
                            mecho --error "Invalid deflection index found."
                            mecho --error "Please reboot your Fritzbox to fix the problem."
                            exit_code=1
                            break
                        fi
                    done
                    techo --end
                else
                    [ -z "${deflectionscount}" ] && exit_code=1
                fi
            ;;
            homeautoinfo)
                # show home automation devices
                mecho --info "Home automation informations ${device}"
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_homeauto" "X_AVM-DE_Homeauto:1"
                idx=0
                while [ true ]
                do
                    if [ "${showfritzindexes:-false}" = "true" ]
                    then
                        count="${idx}"
                    else
                        count=$(expr ${idx} + 1)
                    fi
                    homeautoentry=$(execute_https_soap_request \
                        "GetGenericDeviceInfos" \
                        "<NewIndex>${idx}</NewIndex>")
                    if (echo "${homeautoentry}" | grep -q "Invalid Action")
                    then
                        mecho --warn "Has user smart home rights on fritzbox? Proof in webgui!"
                        exit_code=1
                        output_debugfbfile
                        exit 1
                    fi
                    if (echo "${homeautoentry}" | grep -q "GetGenericDeviceInfosResponse")
                    then
                        homeautoain=$(parse_xml_response "${homeautoentry}" "NewAIN")
                        if [ -n "${searchhomeautoain}" ] && \
                           ! (echo "${homeautoain}" | egrep -q "${searchhomeautoain}")
                        then
                            idx=$(expr ${idx} + 1)
                            continue
                        fi
                        homeautodeviceid=$(parse_xml_response "${homeautoentry}" "NewDeviceId")
                        if [ -n "${searchhomeautodeviceid}" ] && \
                           ! (echo "${homeautodeviceid}" | egrep -q "${searchhomeautodeviceid}")
                        then
                            idx=$(expr ${idx} + 1)
                            continue
                        fi
                        homeautofunctionbitmask=$(parse_xml_response "${homeautoentry}" "NewFunctionBitMask")
                        homeautofirmwareversion=$(parse_xml_response "${homeautoentry}" "NewFirmwareVersion")
                        homeautomanufacturer=$(parse_xml_response "${homeautoentry}" "NewManufacturer")
                        homeautoproductname=$(parse_xml_response "${homeautoentry}" "NewProductName")
                        homeautodevicename=$(parse_xml_response "${homeautoentry}" "NewDeviceName")
                        if [ -n "${searchhomeautodevicename}" ] && \
                           ! (echo "${homeautodevicename}" | egrep -q "${searchhomeautodevicename}")
                        then
                            idx=$(expr ${idx} + 1)
                            continue
                        fi
                        homeautopresent=$(parse_xml_response "${homeautoentry}" "NewPresent")
                        homeautomultimeterisenabled=$(parse_xml_response "${homeautoentry}" "NewMultimeterIsEnabled")
                        homeautomultimeterisvalid=$(parse_xml_response "${homeautoentry}" "NewMultimeterIsValid")
                        homeautomultimeterpower=$(parse_xml_response "${homeautoentry}" "NewMultimeterPower")
                        homeautomultimeterenergy=$(parse_xml_response "${homeautoentry}" "NewMultimeterEnergy")
                        homeautotemperatureisenabled=$(parse_xml_response "${homeautoentry}" "NewTemperatureIsEnabled")
                        homeautotemperatureisvalid=$(parse_xml_response "${homeautoentry}" "NewTemperatureIsValid")
                        homeautotemperaturecelsius=$(parse_xml_response "${homeautoentry}" "NewTemperatureCelsius")
                        homeautotemperatureoffset=$(parse_xml_response "${homeautoentry}" "NewTemperatureOffset")
                        homeautoswitchisenabled=$(parse_xml_response "${homeautoentry}" "NewSwitchIsEnabled")
                        homeautoswitchisvalid=$(parse_xml_response "${homeautoentry}" "NewSwitchIsValid")
                        homeautoswitchstate=$(parse_xml_response "${homeautoentry}" "NewSwitchState")
                        homeautoswitchmode=$(parse_xml_response "${homeautoentry}" "NewSwitchMode")
                        homeautoswitchlock=$(parse_xml_response "${homeautoentry}" "NewSwitchLock")
                        homeautohkrisenabled=$(parse_xml_response "${homeautoentry}" "NewHkrIsEnabled")
                        homeautohkrisvalid=$(parse_xml_response "${homeautoentry}" "NewHkrIsValid")
                        homeautohkristemperature=$(parse_xml_response "${homeautoentry}" "NewHkrIsTemperature")
                        homeautohkrsetventilstatus=$(parse_xml_response "${homeautoentry}" "NewHkrSetVentilStatus")
                        homeautohkrsettemperature=$(parse_xml_response "${homeautoentry}" "NewHkrSetTemperature")
                        homeautohkrreduceventilstatus=$(parse_xml_response "${homeautoentry}" "NewHkrReduceVentilStatus")
                        homeautohkrreducetemperature=$(parse_xml_response "${homeautoentry}" "NewHkrReduceTemperature")
                        homeautohkrcomfortventilstatus=$(parse_xml_response "${homeautoentry}" "NewHkrComfortVentilStatus")
                        homeautohkrcomforttemperature=$(parse_xml_response "${homeautoentry}" "NewHkrComfortTemperature")
                        echo "${count}:AIN                         : ${homeautoain}"
                        echo "${count}:Device ID                   : ${homeautodeviceid}"
                        homeautotypearray=("HANFUN Gerät"           "?" \
                                           "?"                      "?" \
                                           "Alarm-Sensor"           "?" \
                                           "Heizkörperregler"       "Energie Messgerät" \
                                           "Temperatursensor"       "Schaltsteckdose" \
                                           "AVM DECT Repeater"      "Mikrofon" \
                                           "?"                      "HANFUN Unit" \
                                           "?"                      "?")
                        homeautotypebin=""
                        homeautotype=""
                        for typeidx in $(seq 15 -1 0)
                        do
                            homeautotypebit=$(((${homeautofunctionbitmask} >> ${typeidx}) & 1))
                            homeautotypebin=${homeautotypebin}${homeautotypebit}
                            if [ "${homeautotypebit}" -eq 1 ]
                            then
                                if [ -n "${homeautotype}" ]
                                then
                                    homeautotype="${homeautotype}; ${homeautotypearray[${typeidx}]}"
                                else
                                    homeautotype=${homeautotypearray[${idx}]}
                                fi
                            fi
                        done
                        echo "${count}:Functions (decimal/binary)  : ${homeautofunctionbitmask}/${homeautotypebin}"
                        echo "${count}:Functions (plain text)      : ${homeautotype}"
                        echo "${count}:Firmware version            : ${homeautofirmwareversion}"
                        echo "${count}:Manufacturer                : ${homeautomanufacturer}"
                        echo "${count}:Product name                : ${homeautoproductname}"
                        echo "${count}:Device name                 : ${homeautodevicename}"
                        echo "${count}:Connection status           : ${homeautopresent}"
                        echo "${count}:Multimeter enabled          : ${homeautomultimeterisenabled}"
                        echo "${count}:Multimeter valid            : ${homeautomultimeterisvalid}"
                        echo "${count}:Multimeter power (W)        : $(echo "scale=2; ${homeautomultimeterpower} / 100" | bc)"
                        echo "${count}:Multimeter energy (Wh)      : ${homeautomultimeterenergy}"
                        echo "${count}:Temperature enabled         : ${homeautotemperatureisenabled}"
                        echo "${count}:Temperature valid           : ${homeautotemperatureisvalid}"
                        echo "${count}:Temperature (C)             : $(echo "scale=1; ${homeautotemperaturecelsius} / 10" | bc)"
                        echo "${count}:Temperature offset (C)      : $(echo "scale=1; ${homeautotemperatureoffset} / 10" | bc)"
                        echo "${count}:Switch enabled              : ${homeautoswitchisenabled}"
                        echo "${count}:Switch valid                : ${homeautoswitchisvalid}"
                        echo "${count}:Switch status               : ${homeautoswitchstate}"
                        echo "${count}:Switch mode                 : ${homeautoswitchmode}"
                        echo "${count}:Switch lock                 : $(convert_yes_no ${homeautoswitchlock})"
                        echo "${count}:Hkr enabled                 : ${homeautohkrisenabled}"
                        echo "${count}:Hkr valid                   : ${homeautohkrisvalid}"
                        echo "${count}:Hkr temperature (C)         : $(echo "scale=1; ${homeautohkristemperature} / 10" | bc)"
                        echo "${count}:Hkr valve status set        : ${homeautohkrsetventilstatus}"
                        echo "${count}:Hkr temperature set (C)     : $(echo "scale=1; ${homeautohkrsettemperature} / 10" | bc)"
                        echo "${count}:Hkr valve status reduced    : ${homeautohkrreduceventilstatus}"
                        echo "${count}:Hkr temperature reduced (C) : $(echo "scale=1; ${homeautohkrreducetemperature} / 10" | bc)"
                        echo "${count}:Hkr valve status comfort    : ${homeautohkrcomfortventilstatus}"
                        echo "${count}:Hkr temperature comfort (C) : $(echo "scale=1; ${homeautohkrcomforttemperature} / 10" | bc)"
                        idx=$(expr ${idx} + 1)
                    else
                        break
                    fi
                done
            ;;
            homeautoswitch)
                # switch home automation switch to on or off
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_homeauto" "X_AVM-DE_Homeauto:1"
                if [ "${new_enabled}" = "1" ]
                then
                    switchstate="ON"
                else
                    switchstate="OFF"
                fi
                execute_https_soap_request \
                    "SetSwitch" \
                    "<NewAIN>${ain}</NewAIN> \
                     <NewSwitchState>${switchstate}</NewSwitchState>" \
                    | grep -q "SetSwitchResponse"
                exit_code=$?
            ;;
            homepluginfo)
                # show all homeplug/powerline devices
                mecho --info "Homeplug/Powerline devices list ${device}"
                get_url_and_urn "tr64desc.xml" "x_homeplug" "X_AVM-DE_Homeplug:1"
                idx=0
                homeplugcount=$(execute_https_soap_request \
                    "GetNumberOfDeviceEntries" \
                    "")
                homeplugcount=$(parse_xml_response "${homeplugcount}" "NewNumberOfEntries")
                if [ -n "${homeplugcount}" ] && [ "${homeplugcount}" -gt 0 ]
                then
                    techo --begin "4r 4 15 15 18 14r 10"
                    techo --info --row "Idx" "Act" "Name" "Model" "MAC address" "Update: Avail" "Successful"
                    while [ "${idx}" -lt "${homeplugcount}" ]
                    do
                        if [ "${showfritzindexes:-false}" = "true" ]
                        then
                            count="${idx}"
                        else
                            count=$(expr ${idx} + 1)
                        fi
                        homeplugentry=$(execute_https_soap_request \
                            "GetGenericDeviceEntry" \
                            "<NewIndex>${idx}</NewIndex>")
                        if (echo "${homeplugentry}" | grep -q "GetGenericDeviceEntryResponse")
                        then
                            homeplugentrymacaddress=$(parse_xml_response "${homeplugentry}" "NewMACAddress")
                            homeplugentryactive=$(parse_xml_response "${homeplugentry}" "NewActive")
                            homeplugentryname=$(parse_xml_response "${homeplugentry}" "NewName")
                            homeplugentrymodel=$(parse_xml_response "${homeplugentry}" "NewModel")
                            homeplugentryupdateavailable=$(parse_xml_response "${homeplugentry}" "NewUpdateAvailable")
                            homeplugentryupdatesuccessful=$(parse_xml_response "${homeplugentry}" "NewUpdateSuccessful")
                            techo --row \
                                "${count}" \
                                "$(convert_yes_no ${homeplugentryactive})" \
                                "${homeplugentryname}" \
                                "${homeplugentrymodel}" \
                                "${homeplugentrymacaddress}" \
                                "$(convert_yes_no ${homeplugentryupdateavailable})" \
                                "${homeplugentryupdatesuccessful}"
                            idx=$(expr ${idx} + 1)
                        else
                            mecho --error "Invalid homeplug index found."
                            mecho --error "Please reboot your Fritzbox to fix the problem."
                            exit_code=1
                            break
                        fi
                    done
                    techo --end
                else
                    [ -z "${homeplugcount}" ] && exit_code=1
                fi
            ;;
            hostsinfo)
                # show all hosts
                mecho --info "Hosts list ${device}"
                get_url_and_urn "tr64desc.xml" "hosts" "Hosts:1"
                idx=0
                hostscount=$(execute_https_soap_request \
                    "GetHostNumberOfEntries" \
                    "")
                hostscount=$(parse_xml_response "${hostscount}" "NewHostNumberOfEntries")
                if [ -n "${hostscount}" ] && [ "${hostscount}" -gt 0 ]
                then
                    techo --begin "4r 4 4 19 6 18 25"
                    techo --info --row "Idx" "Act" "WOL" "Host name" "Inter" "Mac address" "IP:Type:RemainLeaseTime"
                    while [ "${idx}" -lt "${hostscount}" ]
                    do
                        if [ "${showfritzindexes:-false}" = "true" ]
                        then
                            count="${idx}"
                        else
                            count=$(expr ${idx} + 1)
                        fi
                        hostentry=$(execute_https_soap_request \
                            "GetGenericHostEntry" \
                            "<NewIndex>${idx}</NewIndex>")
                        if (echo "${hostentry}" | grep -q "GetGenericHostEntryResponse")
                        then
                            hostentryipaddress=$(parse_xml_response "${hostentry}" "NewIPAddress")
                            hostentryaddresssource=$(parse_xml_response "${hostentry}" "NewAddressSource")
                            hostentryleasetimeremaining=$(parse_xml_response "${hostentry}" "NewLeaseTimeRemaining")
                            hostentrymacaddress=$(parse_xml_response "${hostentry}" "NewMACAddress")
                            hostentryinterfacetype=$(parse_xml_response "${hostentry}" "NewInterfaceType")
                            if [ "${hostentryinterfacetype}" = "802.11" ]
                            then
                                hostentryinterfacetype="WLAN"
                            fi
                            hostentryactive=$(parse_xml_response "${hostentry}" "NewActive")
                            hostentryhostname=$(parse_xml_response "${hostentry}" "NewHostName")
                            if [ -n "${hostentryipaddress}" ]
                            then
                                if [ "${hostentryaddresssource}" = "DHCP" ]
                                then
                                    if [ "${hostentryleasetimeremaining}" -eq 0 ]
                                    then
                                        hostentryip="${hostentryipaddress}:${hostentryaddresssource}:${hostentryleasetimeremaining}"
                                    else
                                        if [ "$((hostentryleasetimeremaining / 3600))" -eq 0 ]
                                        then
                                            if [ "$((hostentryleasetimeremaining / 60))" -eq 0 ]
                                            then
                                                hostentryip="${hostentryipaddress}:${hostentryaddresssource}:${hostentryleasetimeremaining}s"
                                            else
                                                hostentryip="${hostentryipaddress}:${hostentryaddresssource}:$((hostentryleasetimeremaining / 60))m"
                                            fi
                                        else
                                            hostentryip="${hostentryipaddress}:${hostentryaddresssource}:$((hostentryleasetimeremaining / 3600))h"
                                        fi
                                    fi
                                else
                                    hostentryip="${hostentryipaddress}:${hostentryaddresssource}"
                                fi
                            else
                                hostentryip=""
                            fi
                            if [ -n "${hostentrymacaddress}" ]
                            then
                                hostentrywol=$(execute_https_soap_request \
                                    "X_AVM-DE_GetAutoWakeOnLANByMACAddress" \
                                    "<NewMACAddress>${hostentrymacaddress}</NewMACAddress>")
                                hostentrywol=$(parse_xml_response "${hostentrywol}" "NewAutoWOLEnabled")
                                if [ -z "${hostentrywol}" ]
                                then
                                    exit_code=1
                                fi
                            else
                                hostentrywol="0"
                            fi
                            techo --row \
                                "${count}" \
                                "$(convert_yes_no ${hostentryactive})" \
                                "$(convert_yes_no ${hostentrywol})" \
                                "${hostentryhostname}" \
                                "${hostentryinterfacetype}" \
                                "${hostentrymacaddress}" \
                                "${hostentryip}"
                            idx=$(expr ${idx} + 1)
                        else
                            mecho --error "Invalid host index found."
                            mecho --error "Please reboot your Fritzbox to fix the problem."
                            exit_code=1
                            break
                        fi
                    done
                    techo --end
                else
                    [ -z "${hostscount}" ] && exit_code=1
                fi
            ;;
            autowolswitch)
                # auto wol enable/disable switch for client given by mac
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "hosts" "Hosts:1"
                execute_https_soap_request \
                    "X_AVM-DE_SetAutoWakeOnLANByMACAddress" \
                    "<NewMACAddress>${mac}</NewMACAddress> \
                     <NewAutoWOLEnabled>${new_enabled}</NewAutoWOLEnabled>" \
                    | grep -q "X_AVM-DE_SetAutoWakeOnLANByMACAddressResponse"
                exit_code=$?
            ;;
            autowolinfo)
                # informations about auto wol configuration of client given by mac
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "hosts" "Hosts:1"
                autowolinfo=$(execute_https_soap_request \
                    "X_AVM-DE_GetAutoWakeOnLANByMACAddress" \
                    "<NewMACAddress>${mac}</NewMACAddress>")
                if (echo "${autowolinfo}" | grep -q "X_AVM-DE_GetAutoWakeOnLANByMACAddressResponse")
                then
                    autowolinfoenable=$(parse_xml_response "${autowolinfo}" "NewAutoWOLEnabled")
                    mecho --info "Auto WOL informations ${device}"
                    echo "Auto WOL for Client ${mac} enabled : $(convert_yes_no ${autowolinfoenable})"
                else
                    exit_code=1
                fi
            ;;
            wolclient)
                # wake on lan client given by mac
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "hosts" "Hosts:1"
                execute_https_soap_request \
                    "X_AVM-DE_WakeOnLANByMACAddress" \
                    "<NewMACAddress>${mac}</NewMACAddress>" \
                    | grep -q "X_AVM-DE_WakeOnLANByMACAddressResponse"
                exit_code=$?
            ;;
            ftpswitch|smbswitch|nasswitch)
                # ftp/smb/nas server enable/disable switch
                # On nasswitch command do SMB first
                if [ "${command}" = "ftpswitch" ]
                then
                    servertype="FTP"
                else
                    servertype="SMB"
                fi
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_storage" "X_AVM-DE_Storage:1"
                execute_https_soap_request \
                    "Set${servertype}Server" \
                    "<New${servertype}Enable>${new_enabled}</New${servertype}Enable>" \
                    | grep -q "Set${servertype}ServerResponse"
                exit_code=$?
                if [ "${command}" = "nasswitch" ] && [ "${exit_code}" = "0" ]
                then
                    execute_https_soap_request \
                        "SetFTPServer" \
                        "<NewFTPEnable>${new_enabled}</NewFTPEnable>" \
                        | grep -q "SetFTPServerResponse"
                    exit_code=$?
                fi
                # check media server/nas server dependencies
                storageinfo=$(execute_https_soap_request \
                    "GetInfo" \
                    "")
                if (echo "${storageinfo}" | grep -q "GetInfoResponse")
                then
                    get_url_and_urn "tr64desc.xml" "x_upnp" "X_AVM-DE_UPnP:1"
                    upnpmediainfo=$(execute_https_soap_request \
                        "GetInfo" \
                        "")
                    if (echo "${upnpmediainfo}" | grep -q "GetInfoResponse")
                    then
                        if ([ "$(parse_xml_response "${storageinfo}" "NewFTPEnable")" -eq 0 ] ||
                            [ "$(parse_xml_response "${storageinfo}" "NewSMBEnable")" -eq 0 ]) &&
                           [ "$(parse_xml_response "${upnpmediainfo}" "NewUPnPMediaServer")" -eq 1 ]
                        then
                            mecho -warn "NAS server is disabled in fritzbox therefore Media server will not work."
                            mecho -warn "Activate NAS server in webgui or use: ${0} nasswitch --active"
                        fi
                    else
                        exit_code=1
                    fi
                else
                    exit_code=1
                fi
            ;;
            ftpwanswitch)
                # ftp wan enable/disable switch
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_storage" "X_AVM-DE_Storage:1"
                if [ -z "${ftpwansslonlyon}" ]
                then
                    storageinfo=$(execute_https_soap_request \
                        "GetInfo" \
                        "")
                    if (echo "${storageinfo}" | grep -q "GetInfoResponse")
                    then
                        ftpwansslonlystatus=$(parse_xml_response "${storageinfo}" "NewFTPWANSSLOnly")
                    fi
                else
                    ftpwansslonlystatus="${ftpwansslonlyon}"
                fi
                if [ -n "${ftpwansslonlystatus}" ]
                then
                    # maybe faulty in fritzbox; have to reverse parameters
                    if [ "${FBREVERSEFTPWAN}" = "true" ]
                    then
                        execute_https_soap_request \
                            "SetFTPServerWAN" \
                            "<NewFTPWANEnable>${ftpwansslonlystatus}</NewFTPWANEnable>
                             <NewFTPWANSSLOnly>${new_enabled}</NewFTPWANSSLOnly>" \
                            | grep -q "SetFTPServerWANResponse"
                    else
                        execute_https_soap_request \
                            "SetFTPServerWAN" \
                            "<NewFTPWANEnable>${new_enabled}</NewFTPWANEnable>
                             <NewFTPWANSSLOnly>${ftpwansslonlystatus}</NewFTPWANSSLOnly>" \
                            | grep -q "SetFTPServerWANResponse"
                    fi
                    exit_code=$?
                else
                    exit_code=1
                fi
            ;;
            ftpwansslswitch)
                # ssl only on ftp wan enable/disable switch
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_storage" "X_AVM-DE_Storage:1"
                if [ -z "${ftpwanon}" ]
                then
                    storageinfo=$(execute_https_soap_request \
                        "GetInfo" \
                        "")
                    if (echo "${storageinfo}" | grep -q "GetInfoResponse")
                    then
                        ftpwanstatus=$(parse_xml_response "${storageinfo}" "NewFTPWANEnable")
                    fi
                else
                    ftpwanstatus="${ftpwanon}"
                fi
                if [ -n "${ftpwanstatus}" ]
                then
                    # maybe faulty in fritzbox; have to reverse parameters
                    if [ "${FBREVERSEFTPWAN}" = "true" ]
                    then
                        execute_https_soap_request \
                            "SetFTPServerWAN" \
                            "<NewFTPWANEnable>${new_enabled}</NewFTPWANEnable>
                             <NewFTPWANSSLOnly>${ftpwanstatus}</NewFTPWANSSLOnly>" \
                            | grep -q "SetFTPServerWANResponse"
                    else
                        execute_https_soap_request \
                            "SetFTPServerWAN" \
                            "<NewFTPWANEnable>${ftpwanstatus}</NewFTPWANEnable>
                             <NewFTPWANSSLOnly>${new_enabled}</NewFTPWANSSLOnly>" \
                            | grep -q "SetFTPServerWANResponse"
                    fi
                    exit_code=$?
                else
                    exit_code=1
                fi
            ;;
            storageinfo)
                # informations about storage
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_storage" "X_AVM-DE_Storage:1"
                storageinfo=$(execute_https_soap_request \
                    "GetInfo" \
                    "")
                if (echo "${storageinfo}" | grep -q "GetInfoResponse")
                then
                    storageinfoftpenable=$(parse_xml_response "${storageinfo}" "NewFTPEnable")
                    storageinfoftpstatus=$(parse_xml_response "${storageinfo}" "NewFTPStatus")
                    storageinfosmbenable=$(parse_xml_response "${storageinfo}" "NewSMBEnable")
                    storageinfoftpwanenable=$(parse_xml_response "${storageinfo}" "NewFTPWANEnable")
                    storageinfoftpwansslonly=$(parse_xml_response "${storageinfo}" "NewFTPWANSSLOnly")
                    storageinfoftpwanport=$(parse_xml_response "${storageinfo}" "NewFTPWANPort")
                    mecho --info "Storage informations ${device}"
                    echo "FTP enabled      : $(convert_yes_no ${storageinfoftpenable})"
                    echo "FTP status       : ${storageinfoftpstatus}"
                    echo "FTP WAN enabled  : $(convert_yes_no ${storageinfoftpwanenable})"
                    echo "FTP WAN SSL only : $(convert_yes_no ${storageinfoftpwansslonly})"
                    echo "FTP WAN port     : ${storageinfoftpwanport}"
                    echo "SMB enabled      : $(convert_yes_no ${storageinfosmbenable})"
                else
                    exit_code=1
                fi
            ;;
            upnpswitch)
                # upnp status messages enable/disable switch
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_upnp" "X_AVM-DE_UPnP:1"
                if [ -z "${mediaon}" ]
                then
                    upnpmediainfo=$(execute_https_soap_request \
                        "GetInfo" \
                        "")
                    if (echo "${upnpmediainfo}" | grep -q "GetInfoResponse")
                    then
                        mediastatus=$(parse_xml_response "${upnpmediainfo}" "NewUPnPMediaServer")
                    fi
                else
                    mediastatus="${mediaon}"
                fi
                if [ -n "${mediastatus}" ]
                then
                    execute_https_soap_request \
                        "SetConfig" \
                        "<NewEnable>${new_enabled}</NewEnable>
                         <NewUPnPMediaServer>${mediastatus}</NewUPnPMediaServer>" \
                        | grep -q "SetConfigResponse"
                    exit_code=$?
                else
                    exit_code=1
                fi
            ;;
            mediaswitch)
                # media server enable/disable switch
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_upnp" "X_AVM-DE_UPnP:1"
                if [ -z "${upnpon}" ]
                then
                    upnpmediainfo=$(execute_https_soap_request \
                        "GetInfo" \
                        "")
                    if (echo "${upnpmediainfo}" | grep -q "GetInfoResponse")
                    then
                        upnpstatus=$(parse_xml_response "${upnpmediainfo}" "NewEnable")
                    fi
                else
                    upnpstatus="${upnpon}"
                fi
                if [ -n "${upnpstatus}" ]
                then
                    execute_https_soap_request \
                        "SetConfig" \
                        "<NewEnable>${upnpstatus}</NewEnable>
                         <NewUPnPMediaServer>${new_enabled}</NewUPnPMediaServer>" \
                        | grep -q "SetConfigResponse"
                    exit_code=$?
                else
                    exit_code=1
                fi
                # check if nas server is enabled
                if [ "${new_enabled}" -eq 1 ] && [ "${exit_code}" -eq 0 ]
                then
                    get_url_and_urn "tr64desc.xml" "x_storage" "X_AVM-DE_Storage:1"
                    storageinfo=$(execute_https_soap_request \
                        "GetInfo" \
                        "")
                    if (echo "${storageinfo}" | grep -q "GetInfoResponse")
                    then
                        if [ "$(parse_xml_response "${storageinfo}" "NewFTPEnable")" -eq 0 ] ||
                           [ "$(parse_xml_response "${storageinfo}" "NewSMBEnable")" -eq 0 ]
                        then
                            mecho -warn "NAS server is disabled in fritzbox therefore Media server will not work."
                            mecho -warn "Activate NAS server in webgui or use: ${0} nasswitch --active"
                        fi
                    else
                        exit_code=1
                    fi
                fi
            ;;
            upnpmediainfo)
                # informations about upnp media server storage
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_upnp" "X_AVM-DE_UPnP:1"
                upnpmediainfo=$(execute_https_soap_request \
                    "GetInfo" \
                    "")
                if (echo "${upnpmediainfo}" | grep -q "GetInfoResponse")
                then
                    upnpmediainfoenable=$(parse_xml_response "${upnpmediainfo}" "NewEnable")
                    upnpmediainfomediaserver=$(parse_xml_response "${upnpmediainfo}" "NewUPnPMediaServer")
                    mecho --info "UPnP media server informations ${device}"
                    echo "UPnP status messagess     : $(convert_yes_no ${upnpmediainfoenable})"
                    echo "UPnP Media Server enabled : $(convert_yes_no ${upnpmediainfomediaserver})"
                else
                    exit_code=1
                fi
            ;;
            taminfo)
                # informations about tam
                mecho --info "Answering machine informations ${device}"
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_tam" "X_AVM-DE_TAM:1"
                tamfile=$(execute_https_soap_request \
                        "GetMessageList" \
                        "<NewIndex>0</NewIndex>")
                tamfile=$(parse_xml_response "${tamfile}" "NewURL")
                if [ -n "${tamfile}" ]
                then
                    tamfile="${tamfile:0:${#tamfile}-1}"
                fi
                idx=0
                while [ true ]
                do
                    taminfo=$(execute_https_soap_request \
                        "GetInfo" \
                        "<NewIndex>${idx}</NewIndex>")
                    if (echo "${taminfo}" | grep -q "GetInfoResponse")
                    then
                        taminfoenabled=$(parse_xml_response "${taminfo}" "NewEnable")
                        taminfoname=$(parse_xml_response "${taminfo}" "NewName")
                        taminfotamrunning=$(parse_xml_response "${taminfo}" "NewTAMRunning")
                        taminfostick=$(parse_xml_response "${taminfo}" "NewStick")
                        taminfostatus=$(parse_xml_response "${taminfo}" "NewStatus")
                        taminfocapacity=$(parse_xml_response "${taminfo}" "NewCapacity")
                        if [ "${idx}" -eq 0 ]
                        then
                            echo "Running         : $(convert_yes_no ${taminfotamrunning})"
                            if [ $((taminfostatus & 2)) -eq 0 ]
                            then
                                echo "Capacity        : ${taminfocapacity} minute(s)"
                            else
                                echo "Capacity        : ${taminfocapacity} minute(s); No space left!"
                            fi
                            echo -n "Using USB stick : "
                            case "${taminfostick}"
                            in
                                0|1)
                                    echo "$(convert_yes_no ${taminfostick})"
                                ;;
                                2)
                                    echo  "USB stick available but folder avm_tam missing!"
                                ;;
                            esac
                            techo --begin "4r 4 36 17r 9 6r 4r"
                            techo --info --row "Idx" "Act" "Name" "Visible in WebUI" "Messages" "total" "new"
                        fi
                        if [ -n "${tamfile}" ]
                        then
                            tammessagelist=$(wget -q -O - ${tamfile}${idx})
                            tammessagestotal=$(echo "${tammessagelist}" | grep -o "<Message>" | wc -l)
                            tammessagesnew=$(echo "${tammessagelist}" | grep -o "<New>0</New>" | wc -l)
                        else
                            tammessagestotal="?"
                            tammessagesnew="?"
                        fi
                        techo --row \
                            "${idx}" \
                            "$(convert_yes_no ${taminfoenabled})" \
                            "${taminfoname}" \
                            "$(convert_yes_no $((${taminfostatus} >> 15)))" \
                            "" \
                            "${tammessagestotal}" \
                            "${tammessagesnew}"
                        idx=$(expr ${idx} + 1)
                    else
                        if [ "${idx}" -gt 0 ]
                        then
                            techo --end
                        fi
                        break
                    fi
                done
            ;;
            tamcap)
                # informations tam capacity
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "x_tam" "X_AVM-DE_TAM:1"
                taminfo=$(execute_https_soap_request \
                    "GetInfo" \
                    "<NewIndex>0</NewIndex>")
                taminfocapacity=$(parse_xml_response "${taminfo}" "NewCapacity")
                if [ -n "${taminfocapacity}" ]
                then
                    mecho --info "Answering machine capacity ${device}: ${taminfocapacity} minute(s)"
                else
                    exit_code=1
                fi
            ;;
            tamswitch)
                # tam enable/disable switch
                get_url_and_urn "tr64desc.xml" "x_tam" "X_AVM-DE_TAM:1"
                execute_https_soap_request \
                    "SetEnable" \
                    "<NewIndex>${tamindex}</NewIndex>
                     <NewEnable>${new_enabled}</NewEnable>" \
                    | grep -q "SetEnableResponse"
                exit_code=$?
            ;;
            reconnect)
                # reconnect to internet
                # read control URL and urn from description
                if [ "${FBCONNTYPE:-IP}" = "PPP" ]
                then
                    get_url_and_urn "tr64desc.xml" "wanpppconn1" "WANPPPConnection:1"
                else
                    get_url_and_urn "tr64desc.xml" "wanipconnection1" "WANIPConnection:1"
                fi
                execute_https_soap_request \
                    "ForceTermination" \
                    "" \
                    | grep  -q "DisconnectInProgress"
                exit_code=$?
                sleep 3
                execute_https_soap_request \
                    "RequestConnection" \
                    "" > /dev/null
            ;;
            reboot)
                # reboot fritzbox
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "deviceconfig" "DeviceConfig:1"
                execute_https_soap_request \
                    "Reboot" \
                    "" \
                    | grep  -q "RebootResponse"
                exit_code=$?
            ;;
            savefbconfig)
                # save configuration of fritzbox
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "deviceinfo" "DeviceInfo:1"
                deviceinfo=$(execute_https_soap_request \
                    "GetInfo" \
                    "")
                if (echo "${deviceinfo}" | grep -q "GetInfoResponse")
                then
                    deviceinfomodel=$(parse_xml_response "${deviceinfo}" "NewModelName" | tr " " "_")
                    deviceinfoserial=$(parse_xml_response "${deviceinfo}" "NewSerialNumber")
                    deviceinfosoftware=$(parse_xml_response "${deviceinfo}" "NewSoftwareVersion")
                    # read control URL and urn from description
                    get_url_and_urn "tr64desc.xml" "deviceconfig" "DeviceConfig:1"
                    conffile=$(execute_https_soap_request \
                        "X_AVM-DE_GetConfigFile" \
                        "<NewX_AVM-DE_Password>${fbconffilepassword}</NewX_AVM-DE_Password>")
                    conffile=$(parse_xml_response "${conffile}" "NewX_AVM-DE_ConfigFileUrl")
                    if [ -n "${conffile}" ]
                    then
                        if [ -n "${fbconffileprefix}" ]
                        then
                            fbconffileprefix="${fbconffileprefix}_"
                        fi
                        if [ -n "${fbconffilesuffix}" ]
                        then
                            fbconffilesuffix=".${fbconffilesuffix}"
                        fi
                        fbconffile="${fbconffilepath}/${fbconffileprefix}${deviceinfomodel}_${deviceinfoserial}_${deviceinfosoftware}_$(date +'%Y%m%d_%H%M%S')${fbconffilesuffix}"
                        if [ "${debugfb:-false}" = "true" ]
                        then
                            wget -v --no-check-certificate -O ${fbconffile} ${conffile} > ${debugfbfile}.wget 2>&1
                            wget_errorcode=$?
                            (
                                echo "------------------------------------------------------------------"
                                echo "Download fritzbox configuration file"
                                echo
                                echo "conffile        : ${conffile}"
                                echo
                                echo "fbconffile      : ${fbconffile}"
                                echo
                                echo "wget error code : ${wget_errorcode}"
                                echo
                                cat ${debugfbfile}.wget
                            ) >> ${debugfbfile}
                            rm -f "${debugfbfile}.wget"
                        else
                            wget -q --no-check-certificate -O ${fbconffile} ${conffile}
                            wget_errorcode=$?
                        fi
                        if [ ${wget_errorcode} -ne 0 ]
                        then
                            exit_code=15
                        fi
                    else
                        exit_code=1
                    fi
                else
                    exit_code=1
                fi
            ;;
            updateinfo)
                # informations about firmware update available
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "userif" "UserInterface:1"
                updateinfo=$(execute_https_soap_request \
                    "GetInfo" \
                    "" ; \
                    execute_https_soap_request \
                    "X_AVM-DE_GetInfo" \
                    "")
                if (echo "${updateinfo}" | grep -q "GetInfoResponse") &&
                   (echo "${updateinfo}" | grep -q "X_AVM-DE_GetInfoResponse")
                then
                    updateinfoavail=$(parse_xml_response "${updateinfo}" "NewUpgradeAvailable")
                    updateinfopasswordreq=$(parse_xml_response "${updateinfo}" "NewPasswordRequired")
                    updateinfopasswordusersel=$(parse_xml_response "${updateinfo}" "NewPasswordUserSelectable")
                    updateinfowarrantydate=$(parse_xml_response "${updateinfo}" "NewWarrantyDate")
                    updateinfoversion=$(parse_xml_response "${updateinfo}" "NewX_AVM-DE_Version")
                    updateinfodownloadurl=$(parse_xml_response "${updateinfo}" "NewX-AVM-DE_DownloadURL")
                    updateinfoinfourl=$(parse_xml_response "${updateinfo}" "NewX_AVM-DE_InfoURL")
                    updateinfostate=$(parse_xml_response "${updateinfo}" "NewX_AVM-DE_UpdateState")
                    updateinfolaborversion=$(parse_xml_response "${updateinfo}" "NewX_AVM-DE_LaborVersion")
                    updateinfoautoupdatemode=$(parse_xml_response "${updateinfo}" "NewX_AVM-DE_AutoUpdateMode")
                    updateinfoupdatetime=$(parse_xml_response "${updateinfo}" "NewX_AVM-DE_UpdateTime")
                    updateinfolastfwversion=$(parse_xml_response "${updateinfo}" "NewX_AVM-DE_LastFwVersion")
                    # updateinfolastinfourl=$(parse_xml_response "${updateinfo}" "NewX_AVM-DE_LastInfoUrl")
                    updateinfocurrentfwversion=$(parse_xml_response "${updateinfo}" "NewX_AVM-DE_CurrentFwVersion")
                    updateinfoupdatesuccessful=$(parse_xml_response "${updateinfo}" "NewX_AVM-DE_UpdateSuccessful")
                    mecho --info "Firmware update informations ${device}"
                    echo "Upgrade available : $(convert_yes_no ${updateinfoavail})"
                    echo "Password required : $(convert_yes_no ${updateinfopasswordreq})"
                    echo "User selectable   : $(convert_yes_no ${updateinfopasswordusersel})"
                    # Currently not supported
                    # echo "Warranty date     : ${updateinfowarrantydate}"
                    echo "Version           : ${updateinfoversion}"
                    echo "Download URL      : ${updateinfodownloadurl}"
                    echo "Info URL          : ${updateinfoinfourl}"
                    echo "Update state      : ${updateinfostate}"
                    echo "Labor version     : ${updateinfolaborversion}"
                    echo "Auto update mode  : ${updateinfoautoupdatemode}"
                    echo "Update time       : ${updateinfoupdatetime}"
                    echo "Previous firmware : ${updateinfolastfwversion}"
                    # Allways pointing to the newest firmware not to the previous installed firmware
                    # echo "Previous info url : ${updateinfolastinfourl}"
                    echo "Current firmware  : ${updateinfocurrentfwversion}"
                    echo "Update successful : ${updateinfoupdatesuccessful}"
                else
                    exit_code=1
                fi
            ;;
            tr69info)
                # informations about provider initiated updates via tr69 protocol
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "mgmsrv" "ManagementServer:1"
                tr69info=$(execute_https_soap_request \
                    "GetInfo" \
                    "")
                if (echo "${tr69info}" | grep -q "GetInfoResponse")
                then
                    tr69infourl=$(parse_xml_response "${tr69info}" "NewURL")
                    tr69infousername=$(parse_xml_response "${tr69info}" "NewUsername")
                    tr69infoperiodicinformenable=$(parse_xml_response "${tr69info}" "NewPeriodicInformEnable")
                    tr69infoperiodicinforminterval=$(parse_xml_response "${tr69info}" "NewPeriodicInformInterval")
                    tr69infoperiodicinformtime=$(parse_xml_response "${tr69info}" "NewPeriodicInformTime")
                    tr69infoparameterkey=$(parse_xml_response "${tr69info}" "NewParameterKey")
                    tr69infoparameterhash=$(parse_xml_response "${tr69info}" "NewParameterHash")
                    tr69infoconnectionrequesturl=$(parse_xml_response "${tr69info}" "NewConnectionRequestURL")
                    tr69infoconnectionrequestusername=$(parse_xml_response "${tr69info}" "NewConnectionRequestUsername")
                    tr69infoupgradesmanaged=$(parse_xml_response "${tr69info}" "NewUpgradesManaged")
                    mecho --info "TR-069 management informations ${device}"
                    echo "URL                                  : ${tr69infourl}"
                    echo "User name                            : ${tr69infousername}"
                    echo "Periodic update information          : $(convert_yes_no ${tr69infoperiodicinformenable})"
                    echo "Periodic update information interval : ${tr69infoperiodicinforminterval}"
                    echo "Periodic update information time     : ${tr69infoperiodicinformtime}"
                    echo "Parameter key                        : ${tr69infoparameterkey}"
                    echo "Parameter hash                       : ${tr69infoparameterhash}"
                    echo "Connection request URL               : ${tr69connectionrequesturl}"
                    echo "Connection request user name         : ${tr69connectionrequestusername}"
                    echo "Upgrades managed                     : $(convert_yes_no ${tr69infoupgradesmanaged})"
                else
                    exit_code=1
                fi
            ;;
            deviceinfo)
                # informations about fritzbox
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "deviceinfo" "DeviceInfo:1"
                deviceinfo=$(execute_https_soap_request \
                    "GetInfo" \
                    "")
                if (echo "${deviceinfo}" | grep -q "GetInfoResponse")
                then
                    deviceinfomanufacturer=$(parse_xml_response "${deviceinfo}" "NewManufacturerName")
                    deviceinfomanufactureroui=$(parse_xml_response "${deviceinfo}" "NewManufacturerOUI")
                    deviceinfodescription=$(parse_xml_response "${deviceinfo}" "NewDescription")
                    deviceinfoproductclass=$(parse_xml_response "${deviceinfo}" "NewProductClass")
                    deviceinfomodel=$(parse_xml_response "${deviceinfo}" "NewModelName")
                    deviceinfoserial=$(parse_xml_response "${deviceinfo}" "NewSerialNumber")
                    deviceinfosoftware=$(parse_xml_response "${deviceinfo}" "NewSoftwareVersion")
                    deviceinfohardware=$(parse_xml_response "${deviceinfo}" "NewHardwareVersion")
                    deviceinfospec=$(parse_xml_response "${deviceinfo}" "NewSpecVersion")
                    deviceinfoprovisioning=$(parse_xml_response "${deviceinfo}" "NewProvisioningCode")
                    deviceinfouptime=$(parse_xml_response "${deviceinfo}" "NewUpTime")
                    deviceinfodevicelog=$(parse_xml_response "${deviceinfo}" "NewDeviceLog" | head -1)
                    deviceinfodevicelog=$(convert_html_entities "${deviceinfodevicelog}")
                    mecho --info "Fritzbox informations ${device}"
                    echo "Manufacturer               : ${deviceinfomanufacturer}"
                    echo "Manufacturer OUI           : ${deviceinfomanufactureroui}"
                    echo "Model                      : ${deviceinfomodel}"
                    echo "Description                : ${deviceinfodescription}"
                    echo "Product class              : ${deviceinfoproductclass}"
                    echo "Serial number              : ${deviceinfoserial}"
                    echo "Software version           : ${deviceinfosoftware}"
                    echo "Hardware version           : ${deviceinfohardware}"
                    echo "Spec version               : ${deviceinfospec}"
                    echo "Provisioning code          : ${deviceinfoprovisioning}"
                    echo -n "Uptime                     : $((deviceinfouptime / 3600 / 24)) day(s) "
                    echo -n                              "$((deviceinfouptime / 3600 % 24)) hour(s) "
                    echo -n                              "$((deviceinfouptime % 3600 / 60)) minute(s) "
                    echo                                 "$((deviceinfouptime % 60)) second(s)"
                    multilineoutput "Device log (last event)    :" \
                                    "                           :" \
                                    "${deviceinfodevicelog}"
                    if [ "${FBCONNTYPE:-IP}" = "PPP" ]
                    then
                        echo "Connection to internet via : PPPoE"
                    else
                        echo "Connection to internet via : IP network"
                    fi
                else
                    exit_code=1
                fi
            ;;
            devicelog)
                # shows log formatted or raw
                # read control URL and urn from description
                get_url_and_urn "tr64desc.xml" "deviceinfo" "DeviceInfo:1"
                devicelog=$(execute_https_soap_request \
                    "GetDeviceLog" \
                    "")
                if (echo "${devicelog}" | grep -q "GetDeviceLogResponse")
                then
                    devicelog=$(echo "${devicelog}" | sed -E 's/<[/]?NewDeviceLog>//g' | grep -Ev "^<")
                    if [ -z "${rawdevicelog}" ]
                    then
                        mecho --info "Fritzbox log ${device}"
                        while read devicelogline
                        do
                            deviceloglinetimestamp="$(echo ${devicelogline} | cut -d ' ' -f 1-2)"
                            deviceloglineremaining="$(echo ${devicelogline} | cut -d ' ' -f 3-)"
                            multilineoutput "${deviceloglinetimestamp}" \
                                            "" \
                                            "${deviceloglineremaining}"
                        done <<< "${devicelog}"
                    else
                        echo "${devicelog}"
                    fi
                else
                    exit_code=1
                fi
            ;;
            listxmlfiles)
                descfile="tr64desc.xml"
                xmlfile=$(${CURL_BIN} -s "http://${FBIP}:${FBPORT}/${descfile}")
                if [ -n "${xmlfile}" ]
                then
                    if ! (echo "${xmlfile}" | grep -q "404 Not Found")
                    then
                        mecho --info "Available xml files ${device}"
                        header=true
                        echo "${descfile}"
                        echo "${xmlfile}" | \
                            grep -Eo "<SCPDURL>"'([a-zA-Z0-9/\._]*)'"</SCPDURL>" | \
                            sed -e 's/^<SCPDURL>//' -e 's/<\/SCPDURL>.*$//' | \
                            sort -u | sed 's#/#    #g'
                    else
                        error_14_pre="${descfile}"
                    fi
                else
                    exit_code=1
                fi
                descfile=igddesc.xml
                xmlfile=$(${CURL_BIN} -s "http://${FBIP}:${FBPORT}/${descfile}")
                if [ -n "${xmlfile}" ]
                then
                    if ! (echo "${xmlfile}" | grep -q "404 Not Found")
                    then
                        if ! [ ${header} = "true" ]
                        then
                            mecho --info "Available xml files ${device}"
                        fi
                        echo "${descfile}"
                        echo "${xmlfile}" | \
                            grep -Eo "<SCPDURL>"'([a-zA-Z0-9/\._]*)'"</SCPDURL>" | \
                            sed -e 's/^<SCPDURL>//' -e 's/<\/SCPDURL>.*$//' | \
                            sort -u | sed 's#/#    #g'
                    else
                        if [ -n "${error_14_pre}" ]
                        then
                            error_14_pre="${error_14_pre} and ${descfile}"
                        else
                            error_14_pre="${descfile}"
                        fi
                    fi
                else
                    exit_code=1
                fi
                if [ -n "${error_14_pre}" ]
                then
                    error_14="${error_14_pre} ${error_14}"
                    exit_code=14
                fi
            ;;
            showxmlfile)
                xmlfile=$(${CURL_BIN} -s "http://${FBIP}:${FBPORT}/${descfile}")
                if [ -n "${xmlfile}" ]
                then
                    if ! (echo "${xmlfile}" | grep -q "404 Not Found")
                    then
                        # Correction for malformed fritzbox xml files
                        xmlfile=$(echo "${xmlfile}" | sed "s/\(>\)\(<[^/]\)/\1\n\2/g" | sed "s/\(<[/].*>\)\(<[/]\)/\1\n\2/g")
                        if [ -z "${soapfilter}" ]
                        then
                            mecho --info "Content of ${descfile} ${device}"
                            echo "${xmlfile}"
                        else
                            mecho --info "Filtered Content of ${descfile} ${device}"
                            if [ "${descfile}" = "tr64desc.xml" ] || [ "${descfile}" = "igddesc.xml" ]
                            then
                                echo "${xmlfile}" | \
                                    grep -E "^<(serviceType>|controlURL>|SCPDURL>|/service>$)" | \
                                    sed 's#</service>#--------------------#g'
                            else
                                action_found=false
                                argument_found=false
                                action=""
                                argument=""
                                direction=""
                                related=""
                                type=""
                                echo "${xmlfile}" |
                                while read xmlline
                                do
                                    xmltag=$(echo "${xmlline}" | cut -d ">" -f 1 | sed -e "s#^[ \t]*<##g")
                                    xmlvalue=$(echo "${xmlline}" | sed -e "s#[ \t]*</*${xmltag}>[ \t]*##g")
                                    case "${xmltag}"
                                    in
                                        action)
                                            action_found=true
                                            argument_found=false
                                            action=""
                                            argument=""
                                            direction=""
                                            related=""
                                            type=""
                                        ;;
                                        /action)
                                            action_found=false
                                            argument_found=false
                                            action=""
                                            argument=""
                                            direction=""
                                            related=""
                                            type=""
                                        ;;
                                        name)
                                            if [ "${action_found}" = "true" ]
                                            then
                                                if [ "${argument_found}" = "false" ]
                                                then
                                                    action="${xmlvalue}"
                                                    echo "action: ${xmlvalue}"
                                                else
                                                    argument="${xmlvalue}"
                                                fi
                                            fi
                                        ;;
                                        argument)
                                            if [ "${action_found}" = "true" ]
                                            then
                                                argument_found=true
                                                argument=""
                                                direction=""
                                                related=""
                                                type=""
                                            fi
                                        ;;
                                        direction)
                                            if [ "${argument_found}" = "true" ]
                                            then
                                                if [ "${xmlvalue}" = "in" ]
                                                then
                                                    direction=" in:"
                                                else
                                                    if [ "${xmlvalue}" = "out" ]
                                                    then
                                                        direction="out:"
                                                    else
                                                        direction="  ?:"
                                                    fi
                                                fi
                                            fi
                                        ;;
                                        relatedStateVariable)
                                            if [ "${argument_found}" = "true" ]
                                            then
                                                related="${xmlvalue}"
                                            fi
                                        ;;
                                        /argument)
                                            if [ "${action_found}" = "true" ] && [ "${argument_found}" = "true" ] && \
                                               [ -n "${action}" ]
                                            then
                                                # grep -A 2 because sometimes there is defaultValue line between name and dataType
                                                type=$(echo "${xmlfile}" | grep -A 2 -E "^[ /t]*<name>${related}[ \t]*</name>" | \
                                                    sed -ne "s#[ /t]*</*dataType>[ /t]*##gp")
                                                if [ -z "${type}" ]
                                                then
                                                    type="?"
                                                fi
                                                if [ -z "${direction}" ]
                                                then
                                                    direction="  ?"
                                                fi
                                                if [ -z "${argument}" ]
                                                then
                                                    argument="?"
                                                fi
                                                echo "   ${direction} ${argument} ${type}"
                                            fi
                                            argument_found=false
                                            argument=""
                                            direction=""
                                            related=""
                                            type=""
                                        ;;
                                        /actionList)
                                            break
                                        ;;
                                    esac
                                done
                            fi
                        fi
                    else
                        error_14="${descfile} ${error_14}"
                        exit_code=14
                    fi
                else
                    exit_code=1
                fi
            ;;
            mysoaprequest)
                # mysoaprequestfile is read in "parse commands" part of the script
                if [ -n "${controlURL}" ] && [ -n "${serviceType}" ] && [ -n "${action}" ]
                then
                    # execute soap request from file
                    # read control URL and urn from description
                    get_url_and_urn "${descfile:-tr64desc.xml}" "${controlURL}" "${serviceType}"
                    if [ "${type:-https}" = "https" ]
                    then
                        response=$(execute_https_soap_request \
                            "${action}" \
                            "${data}")
                    else
                        response=$(execute_http_soap_request \
                            "${action}" \
                            "${data}")
                    fi
                    if [ -n "${title}" ]
                    then
                        mecho --info "${title} ${device}"
                    fi
                    if [ -n "${search}" ]
                    then
                        if [ "${search}" = "all" ]
                        then
                            echo "${response}" | grep -Eo "^[ \t]*<[a-zA-Z0-9_-]*>.*([ \t]*</[a-zA-Z0-9_-]*>)?" | \
                                sed -e "s#[ \t]*</[a-zA-Z0-9_-]*>[ \t]*##g" | \
                                sed -e "s#^[ \t]*##g" | sed "s#<##1" | sed "s#>#|#1"
                        else
                            for s in ${search}
                            do
                                echo ${s}"|"$(parse_xml_response "${response}" "${s}")
                            done
                        fi
                    else
                        echo "${response}"
                    fi
                    echo "${response}" | grep  -q "${action}Response"
                    exit_code=$?
                else
                    mecho --error "Necessary file not given or not existing or not all needed"
                    mecho --error "parameters given on the command line for command \"${command}\""
                    usage commandline
                    exit_code=12
                    remove_debugfbfile
                    exit 12
                fi
            ;;
        esac
    else
        # fritzbox not available
        exit_code=2
    fi
else
    # curl not available
    exit_code=3
fi

if [ "${exit_code}" -gt 0 ] && [ "${exit_code}" -ne 9 ] && [ "${exit_code}" -ne 10 ]
then
    eval error='$'error_"${exit_code}"
    mecho --error ${error}
fi

output_debugfbfile

exit ${exit_code}
