#!/usr/bin/env python3
"""
TR-064 client for FRITZ!Box routers.

Communicates with FRITZ!Box devices using the TR-064 SOAP protocol
over HTTP(S) with digest authentication.

Environment variables:
    FRITZ_HOST         Hostname or IP (default: fritz.box)
    FRITZ_PORT         HTTP port (default: 49000)
    FRITZ_HTTPS_PORT   HTTPS port (default: 49443)
    FRITZ_USER         Auth username (default: dslf-config)
    FRITZ_PASS         Auth password (required for most operations)
    FRITZ_CONFIG_PASS  Password for config export
    FRITZ_DEBUG        Set to 1 for debug output

Usage examples:
    tr-064.py security-port
    tr-064.py external-ip
    tr-064.py portmapping-count
    tr-064.py portmapping-entry
    tr-064.py portmapping-toggle 1       # 1=enable, 0=disable
    tr-064.py deflection-count
    tr-064.py deflection-list
    tr-064.py deflection-toggle 1        # 1=enable, 0=disable
    tr-064.py export-phonebook
    tr-064.py export-config

Legacy numeric arguments (1-9, 14) are still supported for
backward compatibility.
"""

import os
import sys
import argparse
import xml.etree.ElementTree as ET

import requests
from requests.auth import HTTPDigestAuth

# Suppress InsecureRequestWarning for self-signed certs
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

DEBUG = int(os.environ.get("FRITZ_DEBUG", "0"))

FRITZ_HOST = os.environ.get("FRITZ_HOST", "fritz.box")
FRITZ_PORT = int(os.environ.get("FRITZ_PORT", "49000"))
FRITZ_USER = os.environ.get("FRITZ_USER", "dslf-config")
FRITZ_PASS = os.environ.get("FRITZ_PASS", "")

FRITZ_HTTPS_PORT = int(os.environ.get("FRITZ_HTTPS_PORT", "49443"))

HTTP_URL = f"http://{FRITZ_HOST}:{FRITZ_PORT}/"
HTTPS_URL = f"https://{FRITZ_HOST}:{FRITZ_HTTPS_PORT}/"


def build_soap(action, service, parameter=""):
    """Build a SOAP envelope for a TR-064 request."""
    envelope = (
        '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
        ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        "<s:Body>"
        f'<u:{action} xmlns:u="{service}">'
        f"{parameter}"
        f"</u:{action}>"
        "</s:Body>"
        "</s:Envelope>"
    )
    return envelope.encode("utf-8")


def post_soap(base_url, control_url, service, action, parameter=""):
    """Send a SOAP request and return the response object."""
    headers = {
        "Content-Type": 'text/xml; charset="utf-8"',
        "SOAPAction": f"{service}#{action}",
    }
    data = build_soap(action, service, parameter)

    if DEBUG:
        print(f"\n[DEBUG] URL: {base_url}{control_url}")
        print(f"[DEBUG] Service: {service}")
        print(f"[DEBUG] Action: {action}")
        print(f"[DEBUG] SOAP body:\n{data.decode('utf-8')}")

    response = requests.post(
        url=f"{base_url}{control_url}",
        headers=headers,
        data=data,
        auth=HTTPDigestAuth(FRITZ_USER, FRITZ_PASS),
        verify=False,
    )

    if DEBUG:
        print(f"[DEBUG] Response status: {response.status_code}")
        print(f"[DEBUG] Response body:\n{response.text}")

    return response


def parse_soap_response(response, expect_output=True):
    """
    Parse a SOAP response and return the action-response element.

    Returns the first child of <s:Body> (the action response element),
    or None if expect_output is False.
    """
    if not response.ok:
        print(f"HTTP error: {response.status_code} {response.reason}", file=sys.stderr)
        try:
            root = ET.fromstring(response.content)
            fault = root.find(".//{http://schemas.xmlsoap.org/soap/envelope/}Fault")
            if fault is not None:
                faultstring = fault.findtext("faultstring", "")
                detail = fault.findtext(".//errorDescription", "")
                print(f"SOAP fault: {faultstring} {detail}", file=sys.stderr)
        except ET.ParseError:
            pass
        sys.exit(1)

    if not expect_output:
        return None

    root = ET.fromstring(response.content)

    body = root.find("{http://schemas.xmlsoap.org/soap/envelope/}Body")
    if body is None:
        print("Error: Could not find SOAP Body in response", file=sys.stderr)
        sys.exit(1)

    action_response = list(body)
    if not action_response:
        print("Error: Empty SOAP Body", file=sys.stderr)
        sys.exit(1)

    return action_response[0]


def parse_escaped_xml(text):
    """
    Parse XML that was escaped (entity-encoded) inside a SOAP response.

    Some TR-064 responses embed XML lists as escaped text inside a tag.
    ElementTree already unescapes entities when extracting .text, so
    this just parses the resulting XML string.
    """
    try:
        return ET.fromstring(text)
    except ET.ParseError as e:
        print(f"Error parsing embedded XML: {e}", file=sys.stderr)
        sys.exit(1)


def find_tag_text(element, tag):
    """Find a tag in the element (direct child or descendant) and return its text."""
    # Direct child lookup
    child = element.find(tag)
    if child is not None:
        return child.text

    # Search all descendants, matching local name (ignoring namespace)
    for el in element.iter():
        local_name = el.tag.split("}")[-1] if "}" in el.tag else el.tag
        if local_name == tag:
            return el.text

    return None


# ---- Command implementations ----

def cmd_security_port(_args):
    """Get the HTTPS security port (default: 49443)."""
    response = post_soap(
        HTTP_URL,
        "upnp/control/deviceinfo",
        "urn:dslforum-org:service:DeviceInfo:1",
        "GetSecurityPort",
    )
    result = parse_soap_response(response)
    port = find_tag_text(result, "NewSecurityPort")
    print(f"SSL port: {port}")


def cmd_external_ip(_args):
    """Get the external (WAN) IP address."""
    response = post_soap(
        HTTPS_URL,
        "upnp/control/wanpppconn1",
        "urn:dslforum-org:service:WANPPPConnection:1",
        "GetExternalIPAddress",
    )
    result = parse_soap_response(response)
    ip = find_tag_text(result, "NewExternalIPAddress")
    print(f"External IP Address: {ip}")


def cmd_portmapping_count(_args):
    """Get the number of port mapping entries."""
    response = post_soap(
        HTTPS_URL,
        "upnp/control/wanpppconn1",
        "urn:dslforum-org:service:WANPPPConnection:1",
        "GetPortMappingNumberOfEntries",
    )
    result = parse_soap_response(response)
    count = find_tag_text(result, "NewPortMappingNumberOfEntries")
    print(f"Port mapping number of entries: {count}")


def cmd_portmapping_entry(_args):
    """Get details of port mapping entry at index 0."""
    response = post_soap(
        HTTPS_URL,
        "upnp/control/wanpppconn1",
        "urn:dslforum-org:service:WANPPPConnection:1",
        "GetGenericPortMappingEntry",
        "<NewPortMappingIndex>0</NewPortMappingIndex>",
    )
    result = parse_soap_response(response)
    print("Port mapping entries[0]:")
    for child in result:
        tag = child.tag.split("}")[-1] if "}" in child.tag else child.tag
        print(f"  {tag} = {child.text}")


def cmd_portmapping_toggle(args):
    """Add/enable or disable a port mapping (arg: 1=enable, 0=disable)."""
    toggle = args.toggle
    parameter = (
        "<NewRemoteHost>0.0.0.0</NewRemoteHost>"
        "<NewExternalPort>80</NewExternalPort>"
        "<NewProtocol>TCP</NewProtocol>"
        "<NewInternalPort>80</NewInternalPort>"
        "<NewInternalClient>192.168.1.100</NewInternalClient>"
        "<NewPortMappingDescription>HTTP-Server</NewPortMappingDescription>"
        "<NewLeaseDuration>0</NewLeaseDuration>"
        f"<NewEnabled>{toggle}</NewEnabled>"
    )
    response = post_soap(
        HTTPS_URL,
        "upnp/control/wanpppconn1",
        "urn:dslforum-org:service:WANPPPConnection:1",
        "AddPortMapping",
        parameter,
    )
    ok = response.ok
    action = "Enable" if toggle == "1" else "Disable"
    status = "ok" if ok else "Fehler"
    print(f"Portmapping: {action} {status}")
    if not ok:
        sys.exit(1)


def cmd_deflection_count(_args):
    """Get the number of configured call deflections."""
    response = post_soap(
        HTTPS_URL,
        "upnp/control/x_contact",
        "urn:dslforum-org:service:X_AVM-DE_OnTel:1",
        "GetNumberOfDeflections",
    )
    result = parse_soap_response(response)
    count = find_tag_text(result, "NewNumberOfDeflections")
    print(f"Anzahl Rufumleitungen: {count}")


def cmd_deflection_list(_args):
    """List all configured call deflections."""
    response = post_soap(
        HTTPS_URL,
        "upnp/control/x_contact",
        "urn:dslforum-org:service:X_AVM-DE_OnTel:1",
        "GetDeflections",
    )
    result = parse_soap_response(response)

    # The deflection list is returned as escaped XML inside NewDeflectionList
    deflection_text = find_tag_text(result, "NewDeflectionList")
    if not deflection_text:
        print("No deflections found.")
        return

    list_root = parse_escaped_xml(deflection_text)
    for item in list_root:
        for child in item:
            tag = child.tag.split("}")[-1] if "}" in child.tag else child.tag
            print(f"{tag} = {child.text}")
        print()


def cmd_deflection_toggle(args):
    """Enable or disable call deflection 0 (arg: 1=enable, 0=disable)."""
    toggle = args.toggle
    parameter = (
        "<NewDeflectionId>0</NewDeflectionId>"
        f"<NewEnable>{toggle}</NewEnable>"
    )
    response = post_soap(
        HTTPS_URL,
        "upnp/control/x_contact",
        "urn:dslforum-org:service:X_AVM-DE_OnTel:1",
        "SetDeflectionEnable",
        parameter,
    )
    ok = response.ok
    action = "Enable" if toggle == "1" else "Disable"
    status = "ok" if ok else "Fehler"
    print(f"SetDeflectionEnable[0]: {action} {status}")
    if not ok:
        sys.exit(1)


def cmd_export_phonebook(_args):
    """Export phone book to XML file."""
    response = post_soap(
        HTTPS_URL,
        "upnp/control/x_contact",
        "urn:dslforum-org:service:X_AVM-DE_OnTel:1",
        "GetPhoneBook",
        "<NewPhonebookID>0</NewPhonebookID>",
    )
    result = parse_soap_response(response)
    url = find_tag_text(result, "NewPhonebookURL")

    if not url:
        print("Error: No phone book URL in response", file=sys.stderr)
        sys.exit(1)

    r = requests.get(url, verify=False)
    if not r.ok:
        print(f"Error downloading phone book: {r.status_code}", file=sys.stderr)
        sys.exit(1)

    outfile = "TelefonbuchFritzbox.xml"
    try:
        with open(outfile, "w", encoding="utf-8") as f:
            f.write(r.text)
        print(f"Status Download: ok ({outfile})")
    except IOError as e:
        print(f"Error writing file: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_export_config(_args):
    """Export FRITZ!Box configuration to file."""
    config_pass = os.environ.get("FRITZ_CONFIG_PASS", "")
    if not config_pass:
        print(
            "Error: Set FRITZ_CONFIG_PASS environment variable "
            "to the config export password.",
            file=sys.stderr,
        )
        sys.exit(1)

    response = post_soap(
        HTTPS_URL,
        "upnp/control/deviceconfig",
        "urn:dslforum-org:service:DeviceConfig:1",
        "X_AVM-DE_GetConfigFile",
        f"<NewX_AVM-DE_Password>{config_pass}</NewX_AVM-DE_Password>",
    )
    result = parse_soap_response(response)
    url = find_tag_text(result, "NewX_AVM-DE_ConfigFileUrl")

    if not url:
        print("Error: No config file URL in response", file=sys.stderr)
        sys.exit(1)

    r = requests.get(
        url,
        auth=HTTPDigestAuth(FRITZ_USER, FRITZ_PASS),
        verify=False,
    )
    if not r.ok:
        print(f"Error downloading config: {r.status_code}", file=sys.stderr)
        sys.exit(1)

    outfile = "KonfigurationFritzbox.xml"
    try:
        with open(outfile, "w", encoding="utf-8") as f:
            f.write(r.text)
        print(f"Status Download: ok ({outfile})")
    except IOError as e:
        print(f"Error writing file: {e}", file=sys.stderr)
        sys.exit(1)


# ---- Legacy numeric aliases (backward compatibility) ----

LEGACY_MAP = {
    "1": "security-port",
    "2": "external-ip",
    "3": "portmapping-count",
    "4": "portmapping-entry",
    "5": "portmapping-toggle",
    "6": "deflection-count",
    "7": "deflection-list",
    "8": "deflection-toggle",
    "9": "export-phonebook",
    "14": "export-config",
}

COMMAND_FUNCS = {
    "security-port": cmd_security_port,
    "external-ip": cmd_external_ip,
    "portmapping-count": cmd_portmapping_count,
    "portmapping-entry": cmd_portmapping_entry,
    "portmapping-toggle": cmd_portmapping_toggle,
    "deflection-count": cmd_deflection_count,
    "deflection-list": cmd_deflection_list,
    "deflection-toggle": cmd_deflection_toggle,
    "export-phonebook": cmd_export_phonebook,
    "export-config": cmd_export_config,
}


def main():
    parser = argparse.ArgumentParser(
        description="TR-064 SOAP client for FRITZ!Box routers",
        epilog=(
            "environment variables:\n"
            "  FRITZ_HOST         Hostname/IP (default: fritz.box)\n"
            "  FRITZ_PORT         HTTP port (default: 49000)\n"
            "  FRITZ_HTTPS_PORT   HTTPS port (default: 49443)\n"
            "  FRITZ_USER         Username (default: dslf-config)\n"
            "  FRITZ_PASS         Password\n"
            "  FRITZ_CONFIG_PASS  Password for config export\n"
            "  FRITZ_DEBUG        Set to 1 for debug output\n"
            "\n"
            "Legacy numeric arguments (1-9, 14) are supported for\n"
            "backward compatibility with the original Python 2 script."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    subparsers = parser.add_subparsers(dest="command", help="available commands")

    subparsers.add_parser("security-port", help="Get HTTPS security port")
    subparsers.add_parser("external-ip", help="Get external IP address")
    subparsers.add_parser("portmapping-count", help="Get number of port mappings")
    subparsers.add_parser("portmapping-entry", help="Get port mapping entry details")

    pm_toggle = subparsers.add_parser(
        "portmapping-toggle", help="Enable/disable port mapping"
    )
    pm_toggle.add_argument("toggle", choices=["0", "1"], help="0=disable, 1=enable")

    subparsers.add_parser("deflection-count", help="Get number of call deflections")
    subparsers.add_parser("deflection-list", help="List call deflections")

    df_toggle = subparsers.add_parser(
        "deflection-toggle", help="Enable/disable call deflection"
    )
    df_toggle.add_argument("toggle", choices=["0", "1"], help="0=disable, 1=enable")

    subparsers.add_parser("export-phonebook", help="Export phone book to XML file")
    subparsers.add_parser("export-config", help="Export configuration to file")

    # Translate legacy numeric arguments to named commands
    if len(sys.argv) > 1 and sys.argv[1] in LEGACY_MAP:
        sys.argv[1] = LEGACY_MAP[sys.argv[1]]

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if not FRITZ_PASS:
        print(
            "Warning: FRITZ_PASS not set. Set it via environment variable.",
            file=sys.stderr,
        )

    cmd_func = COMMAND_FUNCS.get(args.command)
    if cmd_func:
        cmd_func(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
