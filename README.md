# lirc2mqtt
Connects a MQTT message broker to a LIRC infrared device.
Up to now, it can just send codes using 'irsend'.

## Prerequisites ##
* LIRC with irsend have to run on your host machine.
* The container needs access to the device '/var/run/lirc/lircd' of host under the same name. On 'docker run' use the option `-v /var/run/lirc/lircd:/var/run/lirc/lircd`
* The lircd.conf must be located in you host system. (Not in the container.)

## MQTT -> LIRC ##
This lirc2mqtt service can just send IR commands. For that it's listening to one MQTT-topic for each of your remotes defined in lirc:
`lirc/\<nameOfRemote\>/send`
To send an key send a message to the corresponding MQTT-topic. You can try it using the commandline clients from mosquitto-clients:
`mosquitto_pub -h localhost -t "lirc/\<nameOfRemote\>/send" -m '{ "send":"once", "commands": ["cmd1", "cmd2", "cmd1"] }'`
`mosquitto_pub -h localhost -t "lirc/\<nameOfRemote\>/send" -m '{ "send":"hold", "time_msec":"1500", "commands": ["vol_up"] }'`
The second will send the command for 1.5 seconds.

## LIRC -> MQTT ##
This service can not recive commands from a IR-remote.

## How to checkout and create a docker container and run it: ##
      cd /opt
      git clone https://github.com/orbifly/lirc2mqtt.git
      cd ./lirc2mqtt/
      docker build -t lirc2mqtt .
      #On your host, create a folder for a config file
      mkdir /opt/config_lirc2mqtt
      #Start the continer once 
      docker run --name my_lirc2mqtt -v /opt/config_lirc2mqtt:/data lirc2mqtt
      #Stop the container after some seconds
      docker container stop my_lirc2mqtt
      #Now there is a file /opt/config_lirc2mqtt/lirc2mqtt.config
      #Edit this file to fit your requirements
      nano /opt/config_lirc2mqtt/lirc2mqtt.config
      #Now the container is ready to run
      docker run --name my_lirc2mqtt -v /opt/config_lirc2mqtt:/data -v /var/run/lirc/lircd:/var/run/lirc/lircd lirc2mqtt
      
### How to integrate in docker-compose: ###
Create a docker-compose.yml or extend a existing one. Add the following lines if you build the container as described above.

    lirc2mqtt:
      image: "lirc2mqtt"
      volumes:
          - /opt/config_lirc2mqtt:/data
          - /var/run/lirc/lircd:/var/run/lirc/lircd
      restart: always

This project fits to [ct-Smart-Home](https://github.com/ct-Open-Source/ct-Smart-Home). A container is available on Docker Hub, so you just have to add the following lines to docker-compose.yml

    lirc2mqtt:
      image: "orbifly/lirc2mqtt:latest-armv7"
      volumes:
        - ./data/lirc2mqtt:/data
        - /var/run/lirc/lircd:/var/run/lirc/lircd
      restart: always

## History ##
I started in 2020 with the [ct-Smart-Home](https://github.com/ct-Open-Source/ct-Smart-Home) and some zigbee devices. Now it is grown including MPD and [Lirc](https://www.lirc.org/). A lot of good stuff I found in this [article](https://www.heise.de/ct/artikel/c-t-Smart-Home-4249476.html) and some related. My smartphone is invlolved by [Tasker](https://play.google.com/store/apps/details?id=net.dinglisch.android.taskerm&hl=de&gl=US) and [M.A.L.P.](https://play.google.com/store/apps/details?id=org.gateshipone.malp&hl=de&gl=US) as frontend for MPD. My desktop frontend for MPD is [Cantata](https://linuxreviews.org/Cantata). When the music player is started, lirc enables my amplifier - it's a Harman/Kardon AVR2000 in use since 2000.
