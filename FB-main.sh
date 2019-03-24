#!/bin/sh
# FB-main.sh
# Version 0.1.4
# --------------------------------------------------------------------------------
script="FB-main"
Debugmsg1=$Debugmsg1"Script-Version          : $0 v0.1.4 \n"
Debugmsg1=$Debugmsg1"verwendbar mit          : FB.common v0.1.5 / FB.cfg v0.1.1 \n"
# --------------------------------------------------------------------------------
# TR-064 aktivieren, Benützer mit User und Passwort anlegen

Debug="1"			 			   # mit "0" deaktivieren, wenn nicht mehr benötigt

ADDONDIR="/usr/local/addons/cuxd"
#COMMON="FB.common"
COMMON="$ADDONDIR/user/FB.common"
. $COMMON
# --------------------------------------------------------------------------------

ID=$(date "+%M%S"$RANDOM)


network_user_devices="$temp/$script@$IP-network_user_devices.txt"
get_network_user_devices_CCU1(){
if [ -f $network_user_devices ]; then
   rm -f $network_user_devices
   Debugmsg1=$Debugmsg1"\n$IP -> network_user_devices: Daten loeschen \n"   
fi
get_SID
echo -n "$($cURL -s $cURL_timout "http://$IP/query.lua?sid=$SID&network=landevice:settings/landevice/list(name,ip,mac,UID,dhcp,wlan,ethernet,active,static_dhcp,manu_name,wakeup,online,speed,wlan_UIDs,auto_wakeup,guest,url,wlan_station_type,wlan_show_in_monitor,plc)" | sed -e 's/\",//g' -e 's/\"//g' > $network_user_devices)"
Debugmsg1=$Debugmsg1"$IP -> network_user_devices: Daten holen ($network_user_devices) \n"
}
get_network_user_devices_CCU2(){
if [ -f $network_user_devices ]; then
	find $temp/ -name "$script@$IP-network_user_devices.txt" -mmin +2 -print0 | xargs -0 rm -f
	Debugmsg1=$Debugmsg1"\n$IP -> network_user_devices: Daten pruefen \n"	
fi
if [ -f $network_user_devices ]; then
	Debugmsg1=$Debugmsg1"$IP -> network_user_devices: Daten vorhanden \n"
else
	get_SID
	echo -n "$($cURL -s $cURL_timout "http://$IP/query.lua?sid=$SID&network=landevice:settings/landevice/list(name,ip,mac,UID,dhcp,wlan,ethernet,active,static_dhcp,manu_name,wakeup,online,speed,wlan_UIDs,auto_wakeup,guest,url,wlan_station_type,wlan_show_in_monitor,plc)" | sed -e 's/\",//g' -e 's/\"//g' > $network_user_devices)"
	Debugmsg1=$Debugmsg1"$IP -> network_user_devices: Daten holen ($network_user_devices) \n"
fi
}

case $1 in
	"test")  		Debugmsg1=$Debugmsg1"test: erfolgreich\n"	
					;;
					
	"WLAN")  		# sh FB-main.sh WLAN state CUX2801234:1
					location="/upnp/control/wlanconfig1"
					uri="urn:dslforum-org:service:WLANConfiguration:1"
					SoapParam='NewEnable'
					if [ $2 = "0" ] || [ $2 = "1" ]; then
						Action='SetEnable'			
					    set_TR064 $2
					else
						Action='GetInfo'
						get_TR064
						TR064=$(echo $TR064_temp | sed -n 's:.*<'$SoapParam'>\(.*\)</'$SoapParam'>.*:\1:p')
						Debugmsg1=$Debugmsg1"get_TR064     : $SoapParam = $TR064 \n"
					    if [ $2 = "state" ]; then 
							set_CUxD_state $TR064 $3 $1
						elif [ $2 = "state1" ]; then 
							set_CCU_SysVar $TR064 $3 $1
						fi
					fi
					;;
	"WLAN5G")		location="/upnp/control/wlanconfig2"
					uri="urn:dslforum-org:service:WLANConfiguration:2"
					SoapParam='NewEnable'
					if [ $2 = "0" ] || [ $2 = "1" ]; then
						Action='SetEnable'			
					    set_TR064 $2
					else
						Action='GetInfo'
						get_TR064
						TR064=$(echo $TR064_temp | sed -n 's:.*<'$SoapParam'>\(.*\)</'$SoapParam'>.*:\1:p')
						Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$SoapParam = $TR064 \n"
					    if [ $2 = "state" ]; then 
							set_CUxD_state $TR064 $3 $1
						elif [ $2 = "state1" ]; then 
							set_CCU_SysVar $TR064 $3 $1
						fi
					fi
					;;
	"WLANGast")		location="/upnp/control/wlanconfig3"
					uri="urn:dslforum-org:service:WLANConfiguration:3"
					SoapParam='NewEnable'
					if [ $2 = "0" ] || [ $2 = "1" ]; then
						Action='SetEnable'			
					    set_TR064 $2
					else
						Action='GetInfo'
						get_TR064
						TR064=$(echo $TR064_temp | sed -n 's:.*<'$SoapParam'>\(.*\)</'$SoapParam'>.*:\1:p')
						Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$SoapParam = $TR064 \n"
					    if [ $2 = "state" ]; then 
							set_CUxD_state $TR064 $3 $1
						elif [ $2 = "state1" ]; then 
							set_CCU_SysVar $TR064 $3 $1
						fi
					fi
					;;
					
	"reconnect")	location="/igdupnp/control/WANIPConn1"
					uri="urn:schemas-upnp-org:service:WANIPConnection:1"
					Action='ForceTermination'
					get_TR064
					;;
	"reboot") 		location="/upnp/control/deviceconfig"
					uri="urn:dslforum-org:service:DeviceConfig:1"
					Action='Reboot'
					get_TR064
					;;
					
	"Status-Verbindungszeit") 	location="/upnp/control/wanpppconn1"
					uri="urn:dslforum-org:service:WANPPPConnection:1"
					Action='GetInfo'
					SoapParam='NewUptime'
					get_TR064
					TR064=$(echo $TR064_temp | sed -n 's:.*<'$SoapParam'>\(.*\)</'$SoapParam'>.*:\1:p')
					minutes_temp=$(echo $(($TR064*100/60)) )
					minutes=$(printf "%03d" $minutes_temp  | sed -e "s:..$:.&:g")		
					hours_temp=$(echo $(($TR064*100/60/60)) )
					hours=$(printf "%03d" $hours_temp  | sed -e "s:..$:.&:g")
					days_temp=$(echo $(($TR064*100/60/60/24)) )
					days=$(printf "%03d" $days_temp  | sed -e "s:..$:.&:g")
					Debugmsg2=$Debugmsg2"get_TR064     : $1/$2/$3/$SoapParam = $TR064 Sekunden / $minutes Minuten / $hours Stunden / $days Tage\n"
					if [ "$3" = "sec" ] || [ "$3" = "" ]; then
						Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$3/$SoapParam = $TR064 Sekunden \n"
						set_CCU_SysVar $TR064 $2 $1
					elif [ "$3" = "min" ]; then
						Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$3/$SoapParam = $minutes Minuten \n"
						set_CCU_SysVar $minutes $2 $1
					elif [ "$3" = "hour" ]; then
						Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$3/$SoapParam = $hours Stunden \n"
						set_CCU_SysVar $hours $2 $1
					elif [ "$3" = "day" ]; then
						Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$3/$SoapParam = $days Tage \n"
						set_CCU_SysVar $days $2 $1
					fi
					;;						
	"Status-IP") 	location="/upnp/control/wanpppconn1"
					uri="urn:dslforum-org:service:WANPPPConnection:1"
					Action='GetInfo'
					SoapParam='NewExternalIPAddress'
					get_TR064
					TR064=$(echo $TR064_temp | sed -n 's:.*<'$SoapParam'>\(.*\)</'$SoapParam'>.*:\1:p')
					Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$SoapParam = $TR064 \n"
					set_CCU_SysVar $TR064 $2 $1
					;;	
	"Status-Verbindung") 	location="/upnp/control/wanpppconn1"
					uri="urn:dslforum-org:service:WANPPPConnection:1"
					Action='GetInfo'
					SoapParam='NewConnectionStatus'
					get_TR064
					TR064=$(echo $TR064_temp | sed -n 's:.*<'$SoapParam'>\(.*\)</'$SoapParam'>.*:\1:p')
					Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$SoapParam = $TR064 \n"
					if [ $TR064 = "Connected" ]; then
						set_CCU_SysVar 1 $2 $1
					else 
						set_CCU_SysVar 0 $2 $1
					fi
					;;	
	"Status-Uptime") 	location="/upnp/control/deviceinfo"
					uri="urn:dslforum-org:service:DeviceInfo:1"
					Action='GetInfo'
					SoapParam='NewUpTime'
					get_TR064
					TR064=$(echo $TR064_temp | sed -n 's:.*<'$SoapParam'>\(.*\)</'$SoapParam'>.*:\1:p')
					minutes_temp=$(echo $(($TR064*100/60)) )
					minutes=$(printf "%03d" $minutes_temp  | sed -e "s:..$:.&:g")		
					hours_temp=$(echo $(($TR064*100/60/60)) )
					hours=$(printf "%03d" $hours_temp  | sed -e "s:..$:.&:g")
					days_temp=$(echo $(($TR064*100/60/60/24)) )
					days=$(printf "%03d" $days_temp  | sed -e "s:..$:.&:g")
					Debugmsg2=$Debugmsg2"get_TR064     : $1/$2/$3/$SoapParam = $TR064 Sekunden / $minutes Minuten / $hours Stunden / $days Tage\n"
					if [ "$3" = "sec" ] || [ "$3" = "" ]; then
						Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$3/$SoapParam = $TR064 Sekunden \n"
						set_CCU_SysVar $TR064 $2 $1
					elif [ "$3" = "min" ]; then
						Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$3/$SoapParam = $minutes Minuten \n"
						set_CCU_SysVar $minutes $2 $1
					elif [ "$3" = "hour" ]; then
						Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$3/$SoapParam = $hours Stunden \n"
						set_CCU_SysVar $hours $2 $1
					elif [ "$3" = "day" ]; then
						Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$3/$SoapParam = $days Tage \n"
						set_CCU_SysVar $days $2 $1
					fi
					;;
				
	"presence")		get_network_user_devices_$CCU
					present1=$(grep "active : 1" -B 7 -A 12 $network_user_devices | grep " name : " | sed -e 's/name ://')
					present2=$(grep "active : 1" -B 7 -A 12 $network_user_devices | grep " name : " | sed -e 's/name : //' | sed -e 's/ //' | grep "$2")
					if [ "$present2" = "$2" ]; then
						Debugmsg1=$Debugmsg1"Anwesend: $2 erkannt\n"
						set_CCU_SysVar 1 $3 
					else
						Debugmsg1=$Debugmsg1"Anwesend: $2 nicht erkannt\n"
						set_CCU_SysVar 0 $3
					fi
					Debugmsg1=$Debugmsg1"\nAlle anwesenden Geraete:\n$present1 \n"
					;;
	"online")		get_network_user_devices_$CCU
					online1=$(grep "online : 1" -B 11 -A 8 $network_user_devices | grep " name : " | sed -e 's/name ://')
					online2=$(grep "online : 1" -B 11 -A 8 $network_user_devices | grep " name : " | sed -e 's/name : //' | sed -e 's/ //' | grep "$2")
					if [ "$online2" = "$2" ]; then
						Debugmsg1=$Debugmsg1"Online: $2 erkannt\n"
						set_CCU_SysVar 1 $3
					else
						Debugmsg1=$Debugmsg1"Online: $2 nicht erkannt\n"
						set_CCU_SysVar 0 $3
					fi
					Debugmsg1=$Debugmsg1"\nAlle online Geraete:\n$online1 \n"
					;;
			

					
	"box") 			location="/upnp/control/deviceinfo"
					uri="urn:dslforum-org:service:DeviceInfo:1"
					Action='GetInfo'
					get_TR064
					;;		


	"UMTS") 		LOGIN
					if [ $2 = "0" ] || [ $2 = "1" ]; then
						PerformPOST "umts:settings/enabled=$2&sid=$SID" "POST"
					elif [ $2 = "state" ]; then 
						get_UMTS_state
						set_CUxD_state "$stateUMTS" $1 $3 $stateUMTS
					fi
					;;

	"DECT")			LOGIN
					if [ $2 = "0" ] || [ $2 = "1" ]; then
						PerformPOST "dect:settings/enabled=$2&sid=$SID" "POST"
					elif [ $2 = "state" ]; then 
						get_DECT_state
						set_CUxD_state "$stateDECT" $1 $3 $stateDECT
					fi
					;;
	"WLANNacht")	LOGIN
					PerformPOST "wlan:settings/night_time_control_no_forced_off=$2&sid=$SID" "POST"
					;;
	
	"WakeOnLan")	LOGIN
					Debugmsg=$Debugmsg"URL: $FritzBoxURL/net/network_user_devices.lua?sid=$SID \n"
					wol=$($WEBCLIENT "$FritzBoxURL/net/network_user_devices.lua?sid=$SID" | grep '"name"] = ' -B2 | grep $2 -B2 |grep mac | sed -e 's/\["//g' -e 's/\"]//g' -e 's/\"//g' -e 's/mac =//' -e 's/,//' -e 's/^[ \t]*//;s/[ \t]*$//')
					Debugmsg=$Debugmsg"Debug:"$wol"\n"
					if [ "$wol" != "" ]; then
						Debugmsg=$Debugmsg"WOL-MAC: $2 erkannt: $wol\n"
						./ether-wake $wol
					else
						Debugmsg=$Debugmsg"WOL-MAC: $2 nicht erkannt\n"
					fi
					;;


	"Status-UMTS") 	LOGIN
					get_UMTS_state
					if [ $stateUMTS = "0" ] || [ $stateUMTS = "1" ] ; then
						Debugmsg=$Debugmsg"$1: $stateUMTS\n"
						set_CCU_SysVar $2 $stateUMTS
					else
						Debugmsg=$Debugmsg"$1: Fehler\n"
					fi
					;;
	"Status-DECT") 	LOGIN
					get_DECT_state
					if [ $stateDECT = "0" ] || [ $stateDECT = "1" ] ; then
						Debugmsg=$Debugmsg"$1: $stateDECT\n"
						set_CCU_SysVar $2 $stateDECT
					else
						Debugmsg=$Debugmsg"$1: Fehler\n"
					fi
					;;


	"Status-WLANZeitschaltung") 	LOGIN
					Debugmsg=$Debugmsg"URL: $FritzBoxURL/system/wlan_night.lua?sid=$SID \n"
					status=$($WEBCLIENT "$FritzBoxURL/system/wlan_night.lua?sid=$SID" | grep 'name="active" id="uiActive"')
					if echo $status | grep -q 'id="uiActive" checked>' ; then
						Debugmsg=$Debugmsg"Status-WLANZeitschaltung: an\n"
						set_CCU_SysVar $2 "1"
					else
						Debugmsg=$Debugmsg"Status-WLANZeitschaltung: aus\n"
						set_CCU_SysVar $2 "0"
					fi
					;;


	*) 				Debugmsg1=$Debugmsg1"MAIN :  ERROR - Bitte wie folgt aufrufen: \n"
					Debugmsg1=$Debugmsg1"        ./FB-main.sh BEFEHL WERT (0=aus|1=ein) \n"
					Debugmsg1=$Debugmsg1"        Verfuegbar:  \n"
					Debugmsg1=$Debugmsg1"        ./FB-main.sh WLAN [0|1]\n"
					Debugmsg1=$Debugmsg1"        ./FB-main.sh WLAN [state] [CUX2801xxx:x] -> Status an CUxD-Remote (28)\n"				
					Debugmsg1=$Debugmsg1"        ./FB-main.sh WLAN [state1] [Name_der_SysVar] -> SysVar/Logikwert (true/false)\n"					
					Debugmsg1=$Debugmsg1"        ./FB-main.sh WLAN5G [0|1]\n"
					Debugmsg1=$Debugmsg1"        ./FB-main.sh WLAN5G [state] [CUX2801xxx:x] -> Status an CUxD-Remote (28)\n"					
					Debugmsg1=$Debugmsg1"        ./FB-main.sh WLAN5G [state1] [Name_der_SysVar] -> SysVar/Logikwert (true/false)\n"					
					Debugmsg1=$Debugmsg1"        ./FB-main.sh WLANGast [0|1]\n"
					Debugmsg1=$Debugmsg1"        ./FB-main.sh WLANGast [state] [CUX2801xxx:x] -> Status an CUxD-Remote (28)\n"					
					Debugmsg1=$Debugmsg1"        ./FB-main.sh WLANGast [state1] [Name_der_SysVar] -> SysVar/Logikwert (true/false)\n"	
					
					Debugmsg1=$Debugmsg1"        ./FB-main.sh reconnect -> neu mit dem Internet verbinden\n"
					Debugmsg1=$Debugmsg1"        ./FB-main.sh reboot -> Fritzbox neu starten\n"	
					
					Debugmsg1=$Debugmsg1"        ./FB-main.sh Status-Verbindungszeit [Name_der_SysVar] [sec|min|hour|day] -> SysVar/Zahl\n"
					Debugmsg1=$Debugmsg1"        ./FB-main.sh Status-IP [Name_der_SysVar] -> SysVar/Zeichenkette\n"
					Debugmsg1=$Debugmsg1"        ./FB-main.sh Status-Verbindung [Name_der_SysVar] -> SysVar/Logikwert (true/false)\n"
					Debugmsg1=$Debugmsg1"        ./FB-main.sh Status-Uptime [Name_der_SysVar] [sec|min|hour|day] -> SysVar/Zahl\n"
					
					Debugmsg1=$Debugmsg1"        ./FB-main.sh presence [Name_des_Geraetes] [Name_der_SysVar] -> SysVar/Logikwert (true/false)\n"
					Debugmsg1=$Debugmsg1"        ./FB-main.sh online [Name_des_Geraetes] [Name_der_SysVar] -> SysVar/Logikwert (true/false)\n"
					
					Debugmsg2=$Debugmsg2"        -- noch nicht umsetzbar ------------------------------------------------------------------------------------------------------------\n"
					Debugmsg2=$Debugmsg2"        ./FritzBox.sh WLANNacht [0|1] \n"

					Debugmsg2=$Debugmsg2"        ./FritzBox.sh WakeOnLan [Name des LAN Geraetes] - Beispiel: FritzBox.sh WakeOnLan Geraetename \n"

					Debugmsg2=$Debugmsg2"        ./FritzBox.sh DECT [0|1|state  CUX2801xxx:x] \n"
					Debugmsg2=$Debugmsg2"        ./FritzBox.sh UMTS [0|1|state  CUX2801xxx:x]] \n"
					Debugmsg2=$Debugmsg2"        ./FritzBox.sh Status-DECT [Name der logischen Variable (Bool)in der CCU] Beispiel: FritzBox.sh Status-DECT DECTanausVariableCCU \n"
					Debugmsg2=$Debugmsg2"        ./FritzBox.sh Status-UMTS [Name der logischen Variable (Bool)in der CCU] Beispiel: FritzBox.sh Status-UMTS UMTSanausVariableCCU \n"	
					
					Debugmsg2=$Debugmsg2"        ./FritzBox.sh Status-WLANZeitschaltung  [Name der logischen Variable (Bool)in der CCU] Beispiel: FritzBox.sh Status-WLANZeitschaltung WLANZeitschaltungVariableCCU \n"

					EndFritzBoxSkript 4 "Falscher-Parameter-Aufruf-$1-$2-$3-$4";;
esac
EndFritzBoxSkript 0 "Erfolgreich"
