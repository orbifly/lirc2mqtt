#!/bin/bash

cp /lirc2mqtt/LICENSE /data/

# Make it possible to stop by Ctrl+c in interactive container.
cleanup ()
{
  # Kill the most recent background command.
  kill -s SIGTERM $!
  exit 0
}
trap cleanup SIGINT SIGTERM

# Use some central logging functions
logfile="/data/lirc2mqtt.log"
short_logfile()
{
  if [ $( expr "$RANDOM" "%" "100" ) -lt "1" ]
  then
    if [ $( grep "." --count "${logfile}" ) -gt "1000" ]
    then
      temp_file=$( tempfile )
      tail --lines=100 "${logfile}" > ${temp_file}
      mv --force ${temp_file} ${logfile}
    fi
  fi
}

log_info()
{
  if [ "${debug}" != "0" ]
  then
    short_logfile
    echo "$1"
    date "+%x %X : $1" >> ${logfile}
  fi
}

log_error()
{
  short_logfile
  echo "$1" >&2
  date "+%x %X : $1" >> ${logfile}
}


mqtt_server="localhost"
mqtt_base_topic="lirc"
mqtt_user=""
mqtt_password=""
debug="1"
if [ -f "/data/lirc2mqtt.config" ]
then
  # Read parameters from config file
  eval "$( grep --regexp="^[a-z][a-z_]*='[^']*'" "/data/lirc2mqtt.config" )"
  log_info "Read parameters from '/data/lirc2mqtt.config'"
else
  if [ -f "./example.config" ]
  then
    log_info "Create config file: /data/lirc2mqtt.config"
    cp "./example.config" "/data/lirc2mqtt.config"
  fi
fi
invalidate_file=$( tempfile )

read_parameters()
{
  while [ $# -gt 0 ]       #Solange die Anzahl der Parameter ($#) größer 0
  do
    log_info "Option: $1"
    option_name=$( echo $1 | sed "s#\(--.*=\).*\$#\1#" )
    option_value=$( echo $1 | sed "s#--.*=\(.*\)\$#\1#" )
    case "${option_name}" in
      "--mqtt-server=")
        mqtt_server="${option_value}"
      ;;
      "--mqtt-base-topic=")
        mqtt_base_topic="${option_value}"
      ;;
      "--mqtt_user=")
        mqtt_user="${option_value}"
      ;;
      "--mqtt_password=")
        mqtt_password="${option_value}"
      ;;
      "--debug=")
        debug="${option_value}"
      ;;
      "*")
        log_error "Unknown command line option: \"$1\""
        exit 1
      ;;
    esac
    
    shift                  #Parameter verschieben $2->$1, $3->$2, $4->$3,...
  done
}

read_parameters "$@"

if [ "${debug}" != "0" ]
then
  echo "debug = ${debug}"
  echo "mqtt_server = ${mqtt_server}"
  echo "mqtt_base_topic = ${mqtt_base_topic}"
  echo "mqtt_user = ${mqtt_user}"
  echo "mqtt_password = ${mqtt_password}"
fi

# Parameter $1 is the remote defined in lirc.
# Parameter $2 is the line sent by mqtt.
interprete_mqtt_command()
{
  remote="$1"
  line="$2"
  log_info "interprete_mqtt_command( '${remote}', '${line}' )"
  ##strip and remove brackets
  #line=$( echo "${line}" | sed "s#^ *\[\(.*\)\] *\$#\1#" )
  ##make it a line with quoted commands
  #options=$( echo "${line}" | sed  -e "s#[\"]##g" -e "s#[, ]#\" \"#g" -e "s#^#\"#;s#\$#\"#" )
  #log_info "Full command line is 'irsend send_once \"${remote}\" ${options}'."
  ##Use xargs to interprete the options string as a list of strings
  #echo "SEND_ONCE \"${remote}\" ${options}" | xargs irsend
  #Possible commands:
  # { "send":"once", "commands": ["cmd1", "cmd2", "cmd1"] }
  # { "send":"hold", "time_msec":"1500", "commands": ["cmd1", "cmd2", "cmd1"] }
  #strip spaces
  send=$( echo "${line}" | jq --compact-output --raw-output ".send" )
  time_msec=$( echo "${line}" | jq --compact-output --raw-output ".time_msec" )
  commands=$( echo "${line}" | jq --compact-output '.commands | .[]' )
  if [ "${time_msec}" != "null"  -a  "$( echo "${time_msec}" | sed "s#[^0-9]*\([0-9]\+\).*#\1#" )" = "" ]
  then
    log_error "The value of 'time_msec' has to contain a number. '${time_msec}' isn't a valid value"
    return 1
  fi
  if [ "${time_msec}" != "null"  -a  "${time_msec}" != "" ]
  then
    if [ "${time_msec}" -ge "60000" ]
    then
      echo "The value of 'time_msec' is '${time_msec}' that's one minute or more. Will be clamped to 60 seconds."
      time_msec="60000"
    fi
  fi
  if [ "${commands}" = "" ]
  then
    log_error "The attribute 'commands' needs to contain at least on key to send."
    return 2
  fi

  if [ "${send}" = "hold" ]
  then
    if [ "${time_msec}" != "null" ]
    then
      echo "SEND_START \"${remote}\" ${commands}" | xargs irsend
      sleep "$( expr "${time_msec}" "/" "1000" ).$( expr "${time_msec}" "%" "1000" )"
      echo "SEND_STOP \"${remote}\" ${commands}" | xargs irsend
    else
      log_error "On '{\"send\": \"hold\", ...}' the attribute 'time_msec' is needed as well."
    fi
  fi
  if [ "${send}" = "once" ]
  then
    echo "SEND_ONCE \"${remote}\" ${commands}" | xargs irsend
  fi
  
  if [ "${send}" != "once"  -a  "${send}" != "hold" ]
  then
    log_error "The attribute 'send' needs to have a value 'once' or 'hold'. '${send}' is not valid."
    return 3
  fi
}


# Parameter $1 is the remote defined in Lirc.
loop_for_mqtt_set()
{
  remote="$1"
  log_info "loop_for_mqtt_set(${remote})"
  echo "${remote}" | grep -q "[\\/ \"]"
  if [ "$?" = "0" -o "${remote}" = "" ]
  then
    log_error "A remote named '${remote}' will not work in this system."
    exit 2
  fi
  log_info "Remote name is OK '${remote}'. Getting commands..."
  commands=$( irsend LIST "${remote}" "" | grep "." | sed "s#^[^ ]* ##" )
  log_info "$( echo -e "List of commands in ${remote}:\n${commands}" )"
  for command in $( echo "${commands}" )
  do
    echo "${command}" | grep "[\\/ \"-\[\]]"
    if [ "$?" = "0" -o "${command}" = "" ]
    then
      log_error "A remote command named '${command}' will not work in this system. (Found on remote '${remote}'.)"
      exit 2
    fi
  done
  while [ true ]
  do
    log_info "Start listening for '${mqtt_base_topic}/${remote}/send'."
    while IFS= read -r line
    do
      echo "${remote}" "${line}"
      interprete_mqtt_command "${remote}" "${line}" &
    done < <( mosquitto_sub -h "${mqtt_server}" -t "${mqtt_base_topic}/${remote}/send" -u "${mqtt_user}" -P "${mqtt_password}" )
    log_error "Connection to mqtt lost."
    sleep 60
  done
}

#MQTT test
mosquitto_pub -h "${mqtt_server}" -t "${mqtt_base_topic}" --null-message -u "${mqtt_user}" -P "${mqtt_password}"
if [ "$?" != "0" ]
then
  log_error "Mqtt failed to test host - exit script."
  ping "${mqtt_server}" -c 1
  exit 3
fi

#Get all remotes defined in lirc
list_of_remotes=$( irsend LIST "" "" | grep "." )
num_remotes=$( echo "${list_of_remotes}" | grep -c "^..*" )

log_info "$( echo -e "List of remotes:\n${list_of_remotes}" )"

#Start one process for each remote
#Potential concurrency problems will be solved, when irsend opens '/var/run/lirc/lircd' for writing.
counter="0"
for remote in $( echo "${list_of_remotes}" )
do
  counter=$( expr "${counter}" "+" "1" )
  if [ "${counter}" != "${num_remotes}" ]
  then
    loop_for_mqtt_set "${remote}" &
  else
    #The last remote is looped in main thread
    loop_for_mqtt_set "${remote}"
  fi
done
