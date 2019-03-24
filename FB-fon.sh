#!/bin/sh
# FB-fon.sh
# Version 0.1.0
# --------------------------------------------------------------------------------
script="FB-fon"
Debugmsg1=$Debugmsg1"Script-Version          : $0 v0.1.0 \n"
Debugmsg1=$Debugmsg1"verwendbar mit          : FB.common v0.1.6 / FB.cfg v0.1.1 \n"
# --------------------------------------------------------------------------------
# TR-064 aktivieren, Benützer mit User und Passwort anlegen

Debug="1"			 			   # mit "0" deaktivieren, wenn nicht mehr benötigt

ADDONDIR="/usr/local/addons/cuxd"
#COMMON="FB.common"
COMMON="$ADDONDIR/user/FB.common"
. $COMMON
# --------------------------------------------------------------------------------


ID=$(date "+%M%S"$RANDOM)
Anrufliste="$temp/$script@$IP-Anrufliste.xml"

ANRUFLIST="$temp/FritzBox_Anruferliste.csv"	



get_CallThrough_state(){		# 0 / 1
Debugmsg1=$Debugmsg1"URL: $FritzBoxURL/fon_num/callthrough.lua?sid=$SID \n"
stateCallThrough=$($WEBCLIENT "$FritzBoxURL/fon_num/callthrough.lua?sid=$SID" | grep '"telcfg:settings/CallThrough/Active"' | tr -cd [:digit:])
}


get_FONuser(){
	FONuser=$($WEBCLIENT "$FritzBoxURL/dect/dect_list.lua?sid=$SID" | sed -e 's/\["//g' -e 's/\"]//g' -e 's/\"//g' | grep "Intern = $1" -A4 | grep '_node' | sed 's/.*\(.\{1\}\)$/\1/' )
	Debugmsg1=$Debugmsg1"$FritzBoxURL/dect/dect_list.lua?sid=$SID\nFON=$1 / user=$FONuser\n"
}


case $1 in
	"test")  		get_SID
					;;
	"Anrufliste")	get_SID
					Debugmsg1=$Debugmsg1"$IP -> Anruferliste: Daten holen (http://$IP:49000/calllist.lua?sid=$SID) \n"	
					echo -n $($cURL -s "http://$IP:49000/calllist.lua?sid=$SID") > $Anrufliste
					;;			
	"call") 		# sh FB-fon.sh call number time
					location="/upnp/control/x_voip"
					uri="urn:dslforum-org:service:X_VoIP:1"
					SoapParam='NewX_AVM-DE_PhoneNumber'
					Action='X_AVM-DE_DialNumber'  
					set_TR064 $2
					sleep $3
					Action='X_AVM-DE_DialHangup'
					set_TR064
					;;
	"AB") 			# sh FB-fon.sh AB 0 state1 test
					location="/upnp/control/x_tam"
					uri="urn:dslforum-org:service:X_AVM-DE_TAM:1"
					if [ $3 = "0" ] || [ $3 = "1" ]; then
						Action='SetEnable'         
						set_TR064 "NewIndex" $2 "NewEnable" $3
					else
						Action='GetInfo'
						get_TR064 "NewIndex" $2
						SoapParam='NewEnable'
						TR064=$(echo $TR064_temp | sed -n 's:.*<'$SoapParam'>\(.*\)</'$SoapParam'>.*:\1:p')
						Debugmsg1=$Debugmsg1"get_TR064     : $1/$2/$SoapParam = $TR064 \n"
					    if [ $3 = "state" ]; then 
							set_CUxD_state $TR064 $4 $1
						elif [ $3 = "state1" ]; then 
							set_CCU_SysVar $TR064 $4 $1
						fi
					fi
					;;

					
	"FON-alarm")	LOGIN				# sh FritzBox.sh FON-alarm 610 1 8 Hallo%20Welt
					Zeit=$(date +%H%M)
					Telefon=$(echo $2 | cut -c3- | sed -e "s:.$:6&:g")
					get_FONuser $2
					AlarmClock=$(($3-1))
					tone=$4
					Text="$5"
					PerformPOST "telcfg:settings/Foncontrol/User$FONuser/AlarmRingTone0=$tone&sid=$SID" "POST"
					PerformPOST "telcfg:settings/AlarmClock$AlarmClock/Active=1&sid=$SID" "POST"
					PerformPOST "telcfg:settings/AlarmClock$AlarmClock/Number=$Telefon&sid=$SID" "POST"
					PerformPOST "telcfg:settings/AlarmClock$AlarmClock/Name=$Text&sid=$SID" "POST"
					PerformPOST "telcfg:settings/AlarmClock$AlarmClock/Time=$Zeit&sid=$SID" "POST"
					PerformPOST "telcfg:settings/AlarmClock$AlarmClock/Weekdays=0&sid=$SID" "POST"
					PerformPOST "telcfg:settings/AlarmClock$AlarmClock/Active=0&sid=$SID" "POST"
					Debugmsg1=$Debugmsg1"Telefon: $2 = $Telefon\nText: $Text\n"
					;;
	"FON-RingTone")	LOGIN				# sh FritzBox.sh FON-RingTone 610 0 16   (16=lautlos, 3=standard)
					get_FONuser $2
					PerformPOST "telcfg:settings/Foncontrol/User$FONuser/MSN$3/RingTone=$4&sid=$SID" "POST"
					Debugmsg1=$Debugmsg1"telcfg:settings/Foncontrol/User$FONuser/MSN$3/RingTone=$4&sid=$SID"
					;;
	"FON-Name")		LOGIN				# sh FritzBox.sh FON-Name 610 Name
					get_FONuser $2
					PerformPOST "telcfg:settings/Foncontrol/User$FONuser/Name=$3&sid=$SID" "POST"
					Debugmsg1=$Debugmsg1"telcfg:settings/Foncontrol/User$FONuser/Name=$3&sid=$SID"
					;;


	"CallThrough") 	LOGIN
					if [ $2 = "0" ] || [ $2 = "1" ]; then
						PerformPOST "telcfg:settings/CallThrough/Active=$2&sid=$SID" "POST"
					elif [ $2 = "state" ]; then 
						get_CallThrough_state
						set_CUxD_state "$stateCallThrough" $1 $3 $stateCallThrough
					fi
					;;


	"NACHTRUHE") 	LOGIN
					PerformPOST "box:settings/night_time_control_enabled=$2&sid=$SID" "POST";;
	"KLINGELSPERRE") LOGIN
					PerformPOST "box:settings/night_time_control_ring_blocked=$2&sid=$SID" "POST";;
	"RUFUMLEITUNG") LOGIN 
					PerformPOST "telcfg:settings/CallerIDActions$2/Active=$3&sid=$SID" "POST";;
	"Diversity")	LOGIN 
					PerformPOST "telcfg:settings/Diversity$2/Active=$3&sid=$SID" "POST";;	
	"ANRUFEN") 		LOGIN 
					PerformPOST "telcfg:command/Dial=$2&sid=$SID" "POST";;

	"Anrufliste_alt") 	LOGIN
					$WEBCLIENT "$FritzBoxURL/fon_num/foncalls_list.lua?sid=$SID&csv="  "$FritzBoxU RL/fon_num/foncalls_list.lua?sid=$SID&csv=" >$ANRUFLIST 
					;;
	"Anrufliste2CCU")
					LOGIN
					$WEBCLIENT "$FritzBoxURL/fon_num/foncalls_list.lua?sid=$SID&csv=" >$ANRUFLIST 
					out="<table id='fritz'>"
					count=0
					anzahl=`expr $3 + 1`
					while read line; do
						if [ $count -eq $anzahl ]; then
							break       	   
						fi
						if [ "$count" -gt "0" ]; then
							typ=`echo "$line" | cut -f1 -d';'`
							datum=`echo "$line" | cut -f2 -d';'`
							name=`echo "$line" | cut -f3 -d';'`
							rufnummer=`echo "$line" | cut -f4 -d';'`
							nebenstelle=`echo "$line" | cut -f5 -d';'`
							eigene=`echo "$line" | cut -f6 -d';'`
							dauer=`echo "$line" | cut -f7 -d';'`
							out=$out"<tr><td class='fritz_"$typ"'/><td>"$datum"</td><td>"$name"</td><td>"$rufnummer"</td><td>"$nebenstelle"</td><!--<td>"$eigene"</td>--><td>"$dauer"</td></tr>"
						fi
						count=`expr $count + 1` 
					done < $ANRUFLIST
					out=$out"</table>"
					urlencode=$(echo "$out" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/!/%21/g' -e 's/"/%22/g' -e 's/#/%23/g' -e 's/\$/%24/g' -e 's/\&/%26/g' -e 's/'\''/%27/g' -e 's/(/%28/g' -e 's/)/%29/g' -e 's/\*/%2a/g' -e 's/+/%2b/g' -e 's/,/%2c/g' -e 's/-/%2d/g' -e 's/\./%2e/g' -e 's/\//%2f/g' -e 's/:/%3a/g' -e 's/;/%3b/g' -e 's//%3e/g' -e 's/?/%3f/g' -e 's/@/%40/g' -e 's/\[/%5b/g' -e 's/\\/%5c/g' -e 's/\]/%5d/g' -e 's/\^/%5e/g' -e 's/_/%5f/g' -e 's/`/%60/g' -e 's/{/%7b/g' -e 's/|/%7c/g' -e 's/}/%7d/g' -e 's/~/%7e/g')
					$WEBCLIENT "http://$HOMEMATIC/addons/webmatic/cgi/set.cgi?id=$2&value=$urlencode"
					;;
						
	"Status-KLINGELSPERRE") 	LOGIN
					Debugmsg1=$Debugmsg1"URL: $FritzBoxURL/system/ring_block.lua?sid=$SID\n"
					status=$($WEBCLIENT "$FritzBoxURL/system/ring_block.lua?sid=$SID" | grep 'night_time_control_enabled' | grep -Eo "=.{3}" | sed -e 's/\"//g' -e 's/= //')
					if [ "$status" = "1" ] ; then 
						Debugmsg1=$Debugmsg1"Status-KLINGELSPERRE: an\n"
						set_CCU_SysVar $2 "1"
					else
						Debugmsg1=$Debugmsg1"Status-KLINGELSPERRE: aus\n"
						set_CCU_SysVar $2 "0"
					fi
					;;
				

	"Status-Rufumleitung") 	LOGIN
					Debugmsg1=$Debugmsg1"URL: $FritzBoxURL/fon_num/rul_list.lua?sid=$SID \n"
					status=$($WEBCLIENT "$FritzBoxURL/fon_num/rul_list.lua?sid=$SID" | grep '"telcfg:settings/CallerIDActions' -A1)
					if echo $status | grep -q '\[1\]' ; then
						Debugmsg1=$Debugmsg1"Status-Rufumleitung: aktiv\n"
						set_CCU_SysVar $2 "1"
					else
						Debugmsg1=$Debugmsg1"Status-Rufumleitung: inaktiv\n"
						set_CCU_SysVar $2 "0"
					fi
					;;
	"Weckruf") 		LOGIN 
					PerformPOST "telcfg:settings/AlarmClock$2/Active=$3&sid=$SID" "POST";;	
	"Status-Weckruf") 	LOGIN
					Debugmsg1=$Debugmsg1"URL: $FritzBoxURL/fon_devices/alarm.lua?sid=$SID \n"
					status=$($WEBCLIENT "$FritzBoxURL/fon_devices/alarm.lua?sid=$SID&tab=$2" | grep "telcfg:settings/AlarmClock$2/Active")
					if echo $status | grep -q '"1"' ; then
						Debugmsg1=$Debugmsg1"Status-Weckruf: aktiv\n"
						set_CCU_SysVar $3 "1"
					else
						Debugmsg1=$Debugmsg1"Status-Weckruf: inaktiv\n"
						set_CCU_SysVar $3 "0"
					fi
					;;

	*) 				Debugmsg1=$Debugmsg1"MAIN :  ERROR - Bitte wie folgt aufrufen: \n"
					Debugmsg1=$Debugmsg1"        ./FB-fon.sh BEFEHL WERT (0=aus|1=ein) \n"
					Debugmsg1=$Debugmsg1"        Verfuegbar:  \n"
					Debugmsg1=$Debugmsg1"        ./FB-fon.sh Anrufliste \n"
					Debugmsg1=$Debugmsg1" 		 ./FB-fon.sh call [number] [time] \n"
					Debugmsg1=$Debugmsg1"        ./FB-fon.sh AB [Nummer_des_AB] [state] [CUX2801xxx:x] -> Status an CUxD-Remote (28)\n"				
					Debugmsg1=$Debugmsg1"        ./FB-fon.sh AB [Nummer_des_AB] [state1] [Name_der_SysVar] -> SysVar/Logikwert (true/false)\n"	
										

					Debugmsg2=$Debugmsg2"        -- noch nicht umsetzbar ------------------------------------------------------------------------------------------------------------\n"
					Debugmsg2=$Debugmsg2"        ./FB-fon.sh FON-alarm [610|611|...] [1|2|3] [0|1|...] [Text] -> FB-fon.sh FON-alarm 610 1 8 Hallo%20Welt \n"
					Debugmsg2=$Debugmsg2"        ./FB-fon.sh FON-RingTone [610|611|...] [0|1|...] ->  sh FB-fon.sh FON-RingTone 610 16 (16=lautlos, 3=standard,...)\n"
					Debugmsg2=$Debugmsg2"        ./FB-fon.sh FON-Name [610|611|...] [Name] -> FB-fon.sh FON-Name 610 Name\n"

					Debugmsg2=$Debugmsg2"        ./FB-fon.sh CallThrough [0|1|state  CUX2801xxx:x]] \n"	
					Debugmsg2=$Debugmsg2"        ./FB-fon.sh NACHTRUHE [0|1] \n"
					Debugmsg2=$Debugmsg2"        ./FB-fon.sh KLINGELSPERRE [0|1] \n"

					Debugmsg2=$Debugmsg2"        ./FB-fon.sh RUFUMLEITUNG [0|1|2|3(Rufumleitung)] [0|1] \n"
					Debugmsg2=$Debugmsg2"        ./FB-fon.sh Diversity [0|1|2|3(Rufumleitung)] [0|1] \n"



					Debugmsg2=$Debugmsg2"        ./FB-fon.sh Anrufliste2CCU [0000(HOMEMATIC Webmatic SYSVAR ID)] [Anzahl Eintraege] \n"
					Debugmsg2=$Debugmsg2"        ./FB-fon.sh Status-Rufumleitung [Name der logischen Variable (Bool)in der CCU] Beispiel: FB-fon.sh Status-Rufumleitung RufumleitungVariableCCU \n"
	
					Debugmsg2=$Debugmsg2"        ./FB-fon.sh Status-KLINGELSPERRE [Name der logischen Variable (Bool)in der CCU] Beispiel: FB-fon.sh Status-KLINGELSPERRE KLINGELSPERREVariableCCU \n"
					Debugmsg2=$Debugmsg2"        ./FB-fon.sh Weckruf [0|1|2] [0|1] - Beispiel: Schaltet den ersten Weckruf ein  FB-fon.sh Weckruf 0 1 \n"
					Debugmsg2=$Debugmsg2"        ./FB-fon.sh Status-Weckruf [0|1|2] [Name der logischen Variable (Bool)in der CCU] - Beispiel: FB-fon.sh Status-Weckruf 0 CCUvarWeckruf1 \n"
					
					
					EndFritzBoxSkript 4 "Falscher-Parameter-Aufruf-$1-$2-$3-$4";;
esac
EndFritzBoxSkript 0 "Erfolgreich"
