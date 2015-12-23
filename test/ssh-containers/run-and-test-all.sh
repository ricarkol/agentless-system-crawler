
#!/bin/bash

. all_combinations

GREEN='\033[1;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# CHECK FOR tcpdump
# CHECK FOR DOCKER0
# CHECK FOR DOCKER

# START ALL CONTAINERS
STARTED=0
for i in "${arr[@]}"
do
	CNAME=$i.instance

	# restart the container
	docker rm -f $CNAME > /dev/null 2> /dev/null
	docker run -d -P --name $CNAME $i > /dev/null 2> /dev/null
	sleep 3

	# check if the container is still running
	EXIT_CODE=`docker inspect --format '{{.State.ExitCode}}' ${CNAME}`
	RETVAL=$?
	if [ $RETVAL -ne 0 ] || [ $EXIT_CODE -ne 0 ]
	then
		ON="CRASHED"
	else
		ON="RUNNING"
	fi

	PORT_MAP=`docker PORT $CNAME 22 2> /dev/null || echo 0:1`
	PORT=`echo $PORT_MAP | awk -F: '{print $2}'`

	rm -f trace.txt
	rm -f trace.pcap
	rm -f trace-with-payload.txt
	tcpdump -i docker0 -nnvvXSs 1514 -w trace.pcap 2>/dev/null &
	NGREP_PID=$!
	sleep 3

	# start a connection to the container at port 22
	timeout 3 telnet localhost $PORT >/dev/null 2>/dev/null

	sleep 2
	kill $NGREP_PID >/dev/null 2>/dev/null
	sleep 2

	tcpdump -r trace.pcap -nnvvXSs 1514 > trace-with-payload.txt 2>/dev/null
	tcpdump -r trace.pcap > trace.txt 2>/dev/null

	grep SSH trace-with-payload.txt >/dev/null 2>/dev/null
	if [ $? == 0 ]
	then
		SSHD="SSHD"
	else
		SSHD="other"
	fi

	# if there is no server listening on port 22, and the port is mapped in
	# the container, we typically get something like this:
	#
	# packet 0: ICMP
	# packet 1: ARP request
	# ...
	# packet k: ARP request
	# packet k+1: ---[S]---> (sync)
	# packet k+2: <--[R]---- (reset)
	#
	# So the rule to detect that case will be 2 or less non-ARP packets.
	NON_ARP_PACKET_CNT=`grep -v ARP trace.txt | grep -v ICMP | wc -l | awk '{print $1}'`
	if [ $NON_ARP_PACKET_CNT -gt "2" ]
	then
		LISTENING="listening"
	else
		LISTENING="not-listening"
	fi

	if [ $SSHD == "SSHD" ]
	then
		printf "${GREEN}%-5s %-15s %-8s %s${NC}\n" $SSHD $LISTENING $ON $i
	elif [ $ON == "CRASHED" ]
	then
		printf "${RED}%-5s %-15s %-8s %s${NC}\n" $SSHD $LISTENING $ON $i
	else
		printf "%-5s %-15s %-8s %s\n" $SSHD $LISTENING $ON $i
	fi

	# kill and delete the container
	docker rm -f $CNAME > /dev/null 2> /dev/null
done
