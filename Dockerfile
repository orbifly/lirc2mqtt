# https://docs.docker.com/get-started/part2/#define-a-container-with-a-dockerfile

# Use an official image including 'apt' and 'bash' as parent
FROM debian:buster

# Upgrade and add some software we need: mpc and mqtt client
RUN apt update && apt -y upgrade; apt install -y lirc wget jq && wget https://github.com/hivemq/mqtt-cli/releases/download/v4.4.0/mqtt-cli-4.4.0.deb && apt install -y ./mqtt-cli-4.4.0.deb && apt remove -y wget; apt autoremove -y; rm -rf /var/lib/apt/lists/*

# Set the working directory to /lirc2mqtt
WORKDIR /lirc2mqtt

# Copy needed files into the container at /lirc2mqtt
ADD ./lirc2mqtt.sh /lirc2mqtt/
ADD ./data/lirc2mqtt.config /lirc2mqtt/example.config

VOLUME /data

#Need to be run with    -v /var/run/lirc/lircd:/var/run/lirc/lircd

# Run script when the container launches
CMD ["/lirc2mqtt/lirc2mqtt.sh"]
# All possible options:
# --mqtt-server=
# --mqtt-base-topic=
# --debug=     #set to 1 for some messages
