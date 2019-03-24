#!/bin/sh
# FB-AHA.sh
# Version 0.1.6
# --------------------------------------------------------------------------------
script="FB-AHA"
Debugmsg1=$Debugmsg1"Script-Version          : $0 v0.1.6 \n"
Debugmsg1=$Debugmsg1"verwendbar mit          : FB.common v0.1.6 / FB.cfg v0.1.1 \n"
# --------------------------------------------------------------------------------
# TR-064 aktivieren, Benutzer mit User und Passwort anlegen

Debug="1"			 			   # mit "0" deaktivieren, wenn nicht mehr benÃ¶tigt

ADDONDIR="/usr/local/addons/cuxd"
#COMMON="FB.common"
COMMON="$ADDONDIR/user/FB.common"
. $COMMON
# --------------------------------------------------------------------------------

AHAURL="http://$IP/webservices/homeautoswitch.lua"


set_CUxD_temperature(){
	if [ "$1" != "" ] ; then
		Debugmsg1=$Debugmsg1"set_CUxD_temperature: http://$HOMEMATIC:8181/FritzBox.exe?Status=dom.GetObject%28%27CUxD.$2.SET_TEMPERATURE%27%29.State%28%22$1%22%29 \n"
		$cURL -s $cURL_timout "http://$HOMEMATIC:8181/FritzBox.exe?Status=dom.GetObject%28%27CUxD.$2.SET_TEMPERATURE%27%29.State%28%22$1%22%29"	
	else
		Debugmsg1=$Debugmsg1"$IP -> set_CUxD_temperature: $3/$2 - Fehler, keine Status.\n"
		logger -i -t $0 -p 3 "$IP -> set_CUxD_temperature: $3/$2 - Fehler, keine Status."
	fi
}

get_FBAHA_state(){ 		# 0 / 1 / inval
get_SID
Debugmsg2=$Debugmsg2"URL: $AHAURL?ain=$AIN&switchcmd=getswitchstate&sid=$SID \n"	
stateFBAHA=$($cURL -s "$AHAURL?ain=$AIN&switchcmd=getswitchstate&sid=$SID")
}
get_FBAHA_present(){ 	# 0 / 1
get_SID
Debugmsg2=$Debugmsg2"URL: $AHAURL?ain=$AIN&switchcmd=getswitchpresent&sid=$SID \n"	
presentFBAHA=$($cURL -s $cURL_timout "$AHAURL?ain=$AIN&switchcmd=getswitchpresent&sid=$SID")
}

get_FBAHA_DEVICE_state(){
devicesFBAHA="$temp/$script@$IP-devices.xml"
test="$temp/test.xml"
get_FBAHA_DEVICE_$CCU

response_Name=$(sed -n "/deviceidentifier=$AIN/{s/.*<deviceidentifier=$AIN//;s/<\/device>.*//;p;}" $devicesFBAHA | sed -n 's:.*<name>\(.*\)</name>.*:\1:p' )

get_FBAHA_Celsius=$(sed -n "/deviceidentifier=$AIN/{s/.*<deviceidentifier=$AIN//;s/<\/device>.*//;p;}" $devicesFBAHA | sed -n 's:.*<celsius>\(.*\)</celsius>.*:\1:p' )
response_Celsius=$(printf "%.2i\n" $get_FBAHA_Celsius | sed -e "s:.$:.&:g")

get_FBAHA_Power=$(sed -n "/deviceidentifier=$AIN/{s/.*<deviceidentifier=$AIN//;s/<\/device>.*//;p;}" $devicesFBAHA | sed -n 's:.*<power>\(.*\)</power>.*:\1:p' )
response_Power=$(printf "%.4i\n" $get_FBAHA_Power | sed -e "s:...$:.&:g")

Debugmsg2=$Debugmsg2"\nGeraet: $response_Name / $AIN \n\nPower: $get_FBAHA_Power = $response_Power Watt\nTemperatur: $get_FBAHA_Celsius = $response_Celsius Â°C\n"	
}
get_FBAHA_DEVICE_CCU1(){
if [ -f $devicesFBAHA ]; then
	rm -f $devicesFBAHA
	Debugmsg1=$Debugmsg1"$IP -> FBAHA: Daten loeschen \n"	
fi
get_SID
Debugmsg1=$Debugmsg1"$IP -> FBAHA: Daten holen ($AHAURL?&switchcmd=getdevicelistinfos&sid=$SID) \n"	
echo -n $($cURL -s $cURL_timout "$AHAURL?switchcmd=getdevicelistinfos&sid=$SID" | sed 's|[" ]||g' ) > $devicesFBAHA
}
get_FBAHA_DEVICE_CCU2(){
if [ -f $devicesFBAHA ]; then
	find $temp/ -name "$script@$IP-devices.xml" -mmin +2 -print0 | xargs -0 rm -f
	Debugmsg1=$Debugmsg1"$IP -> FBAHA: Daten pruefen \n"	
fi
if [ -f $devicesFBAHA ]; then
	Debugmsg1=$Debugmsg1"$IP -> FBAHA: Daten vorhanden \n"
else
	get_SID
	Debugmsg1=$Debugmsg1"$IP -> FBAHA: Daten holen ($AHAURL?&switchcmd=getdevicelistinfos&sid=$SID) \n"	
	echo -n $($cURL -s $cURL_timout "$AHAURL?switchcmd=getdevicelistinfos&sid=$SID" | sed 's|[" ]||g' ) > $devicesFBAHA
fi
}

# switch / ain / state / sysvar/cux
case $1 in
	"test")  		Debugmsg1=$Debugmsg1"test: erfolgreich\n"
					get_SID
					logout
					;;
	"switch")  		AIN=$2
					if [ $3 = "0" ] ; then
						get_SID
						$cURL -s $cURL_timout "$AHAURL?ain=$AIN&switchcmd=setswitchoff&sid=$SID"
						Debugmsg2=$Debugmsg2"$AHAURL?ain=$AIN&switchcmd=setswitchoff&sid=$SID\n"
					elif [ $3 = "1" ] ; then
						get_SID
						$cURL -s $cURL_timout "$AHAURL?ain=$AIN&switchcmd=setswitchon&sid=$SID"
						Debugmsg2=$Debugmsg2"$AHAURL?ain=$AIN&switchcmd=setswitchon&sid=$SID\n"
					elif [ $3 = "state" ] ; then
						get_FBAHA_state
						set_CUxD_state $stateFBAHA $4 $1
					elif [ $3 = "state1" ] ; then
						get_FBAHA_state
						get_FBAHA_present
						set_CUxD_state $stateFBAHA $4 $1
						if [ $presentFBAHA = "0" ] || [ $presentFBAHA = "1" ] ; then
							set_CCU_SysVar $presentFBAHA $4-Status $1
							if [ $presentFBAHA = "0" ] ; then
							logger -i -t $0 -p 3 "$IP -> $3/$2 - nicht online"
							fi
						else
							presentFBAHA=2
							set_CCU_SysVar $presentFBAHA $4-Status $1
						fi
					elif [ $3 = "state1-p" ] ; then
						get_FBAHA_state
						get_FBAHA_present
						set_CUxD_state $stateFBAHA $4 $1
						if [ $presentFBAHA = "0" ] || [ $presentFBAHA = "1" ] ; then
							set_CCU_SysVar $presentFBAHA $4-Status $1
							if [ $presentFBAHA = "0" ] ; then
							logger -i -t $0 -p 3 "$IP -> $3/$2 - nicht online"
							fi
						else
							presentFBAHA=2
							set_CCU_SysVar $presentFBAHA $4-Status $1
						fi
						get_FBAHA_DEVICE_state
						if [ $get_FBAHA_Power != "" ] ; then
							set_CCU_SysVar $response_Power $4-Leistung $1
						elif [ $presentFBAHA = "1" ] ; then
							set_CCU_SysVar "" $4-Leistung $1
						fi
					elif [ $3 = "state1-t" ] ; then
						get_FBAHA_state
						get_FBAHA_present
						set_CUxD_state $stateFBAHA $4 $1
						if [ $presentFBAHA = "0" ] || [ $presentFBAHA = "1" ] ; then
							set_CCU_SysVar $presentFBAHA $4-Status $1
							if [ $presentFBAHA = "0" ] ; then
							logger -i -t $0 -p 3 "$IP -> $3/$2 - nicht online"
							fi
						else
							presentFBAHA=2
							set_CCU_SysVar $presentFBAHA $4-Status $1
						fi
						get_FBAHA_DEVICE_state
						if [ $get_FBAHA_Celsius != "" ] ; then
							set_CCU_SysVar $response_Celsius $4-Temperatur $1
						elif [ $presentFBAHA = "1" ] ; then
							set_CCU_SysVar "" $4-Temperatur $1
						fi
					elif [ $3 = "state1-pt" ] ; then
						get_FBAHA_state
						get_FBAHA_present
						set_CUxD_state $stateFBAHA $4 $1
						if [ $presentFBAHA = "0" ] || [ $presentFBAHA = "1" ] ; then
							set_CCU_SysVar $presentFBAHA $4-Status $1
							if [ $presentFBAHA = "0" ] ; then
							logger -i -t $0 -p 3 "$IP -> $3/$2 - nicht online"
							fi
						else
							presentFBAHA=2
							set_CCU_SysVar $presentFBAHA $4-Status $1
						fi
						get_FBAHA_DEVICE_state
						if [ $get_FBAHA_Celsius != "" ]; then
							set_CCU_SysVar $response_Celsius $4-Temperatur $1
						elif [ $presentFBAHA = "1" ] ; then
						 	set_CCU_SysVar "" $4-Temperatur $1
						fi
						if [ $get_FBAHA_Power != "" ] ; then
							set_CCU_SysVar $response_Power $4-Leistung $1
						elif [ $presentFBAHA = "1" ] ; then
							set_CCU_SysVar "" $4-Leistung $1
						fi
					elif [ $3 = "state1-pts" ] ; then
						get_FBAHA_state
						get_FBAHA_present
						set_CUxD_state $stateFBAHA $4 $1
						if [ $stateFBAHA != "" ] ; then
							set_CCU_SysVar $stateFBAHA $4-Schaltzustand $1
						else
							set_CCU_SysVar "" $4-Schaltzustand $1
						fi
						if [ $presentFBAHA = "0" ] || [ $presentFBAHA = "1" ] ; then
							set_CCU_SysVar $presentFBAHA $4-Status $1
							if [ $presentFBAHA = "0" ] ; then
							logger -i -t $0 -p 3 "$IP -> $3/$2 - nicht online"
							fi
						else
							presentFBAHA=2
							set_CCU_SysVar $presentFBAHA $4-Status $1
						fi
						get_FBAHA_DEVICE_state
						if [ $get_FBAHA_Celsius != "" ] ; then
							set_CCU_SysVar $response_Celsius $4-Temperatur $1
						elif [ $presentFBAHA = "1" ] ; then
							set_CCU_SysVar "" $4-Temperatur $1
						fi
						if [ $get_FBAHA_Power != "" ] ; then
							set_CCU_SysVar $response_Power $4-Leistung $1
						elif [ $presentFBAHA = "1" ] ; then
							set_CCU_SysVar "" $4-Leistung $1
						fi
					elif [ $3 = "power" ] ; then 
						get_FBAHA_DEVICE_state
						if [ $get_FBAHA_Power != "" ] ; then
							set_CCU_SysVar $response_Power $4-Leistung $1
						else
							set_CCU_SysVar "" $4-Leistung $1
						fi
					elif [ $3 = "power1" ] ; then 
						get_FBAHA_DEVICE_state
						set_CUxD_state $response_Power $4 $1
					elif [ $3 = "temperature" ] ; then 
						get_FBAHA_DEVICE_state
						if [ $get_FBAHA_Celsius != "" ] ; then
							set_CCU_SysVar $response_Celsius $4-Temperatur $1
						else
							set_CCU_SysVar "" $4-Temperatur $1
						fi
					elif [ $3 = "temperature1" ] ; then 
						get_FBAHA_DEVICE_state
						set_CUxD_state $response_Celsius $4 $1
					elif [ $3 = "temperature2" ] ; then 
						get_FBAHA_DEVICE_state
						set_CUxD_temperature $response_Celsius $4 $1
					else
					logger -i -t $0 -p 3 "$IP -> $1: Fehler"
					fi
					;;

	*) 				Debugmsg1=$Debugmsg1"MAIN :  ERROR - Bitte wie folgt aufrufen: \n"
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh BEFEHL WERT (0=aus|1=ein) \n"
					Debugmsg1=$Debugmsg1"        Verfuegbar:  \n"
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [0|1] -> aus/ein \n"
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [state] [CUX2801xxx:x] -> Status an CUxD-Remote (28)\n"
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [state] [CUX9001xxx:x] -> ein/aus an CUxD (90)State-Monitor Device\n"
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [state1] [CUX2801xxx:x] -> Status an CUxD-Remote (28) und SysVar [CUX2801xxx:x-Status] -> Werteliste: nicht erreichbar;erreichbar;unbekannt\n"
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [state1-p] [CUX2801xxx:x] -> Status an CUxD-Remote (28) und SysVar: [CUX2801xxx:x-Status] [CUX2801xxx:x-Leistung]\n"
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [state1-t] [CUX2801xxx:x] -> Status an CUxD-Remote (28) und SysVar: [CUX2801xxx:x-Status] [CUX2801xxx:x-Temperatur]\n"
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [state1-pt] [CUX2801xxx:x] -> Status an CUxD-Remote (28) und SysVar: [CUX2801xxx:x-Status] [CUX2801xxx:x-Leistung] [CUX2801xxx:x-Temperatur]\n"
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [state1-pts] [CUX2801xxx:x] -> Status an CUxD-Remote (28) und SysVar: [CUX2801xxx:x-Status] [CUX2801xxx:x-Leistung] [CUX2801xxx:x-Temperatur] [CUX2801xxx:x-Schaltzustand]\n"
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [power] [CUX2801xxx:x] -> SysVar [CUX2801xxx:x-Leistung] -> Zahl\n"
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [power1] [CUX9000xxx:x] -> CUxD (90)Transform Device \n"	
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [temperature] [CUX2801xxx:x] -> SysVar [CUX2801xxx:x-Temperatur] -> Zahl\n"		
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [temperature1] [CUX9000xxx:x] -> CUxD (90)Transform Device \n"	
					Debugmsg1=$Debugmsg1"        ./FB-AHA.sh switch [AIN|MAC] [temperature2] [CUX9002xxx:x] -> CUxD (90)Thermostat Device \n"

					EndFritzBoxSkript 4 "Falscher-Parameter-Aufruf-$1-$2-$3-$4";;
esac
EndFritzBoxSkript 0 "Erfolgreich"
