#!/bin/bash

#CONFIG_FILE=setup_env.sh

USAGE="Usage $0 start|stop|delete container_number"

if [ $# -ne 2 ] ; then
    echo $USAGE
    exit 1
fi

re='^[0-9]+$'
if ! [[ $2 =~ $re ]] ; then
   echo "error: container_number must be an integer" >&2; exit 1
fi

if ! [ -f "$CONFIG_FILE" ] ; then
    echo "Cannot open configuration file $CONFIG_FILE"
    exit 1
fi

. $CONFIG_FILE

PROC_ID=$2
INSTANCE_ID=`hostname`_${PROC_ID}
CONTAINER_NAME=${CONSUL_CONT}_${PROC_ID}

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

# get the bond0 or eth0 Address depending on box setup and set-up CONSUL_IP
if [[ -n $(ip -4 -o addr show bond0) ]]; then
       CONSUL_IP=`ip -4 -o addr show bond0 | awk -F '[ /]+' '{ print $4; }'`
       echo "Using bond IP for consul:"  ${CONSUL_IP}
else
       CONSUL_IP=`ip -4 -o addr show eth0 | awk -F '[ /]+' '{ print $4; }'`
       echo "Using eth0 IP for consul:"  ${CONSUL_IP}
fi

BRIDGE_IP=`ip -4 -o addr show docker0 | awk -F '[ /]+' '{ print $4; }'`
echo "Bridge IP: $BRIDGE_IP"

RECURSORS=`awk '/nameserver/ { printf "-recursor %s ", $2; }' < /etc/resolv.conf`
echo "DNS: $RECURSORS"

NODE=`hostname -s | awk -F- '{ OFS="-"; print $(NF-1),$NF; }'`
echo "Consul Node: $NODE"

# compute joins 
JOINS=""
for h in ${CLUSTER[@]}
do
if [ $h != ${CONSUL_IP} ]
then
JOINS="${JOINS} -join $h"
fi
done
echo "Joins: ${JOINS}"

HOST_SUPERVISOR_LOG_DIR=${HOST_CONTAINER_LOG_DIR}/${CONTAINER_NAME}/${SUPERVISOR_DIR}
mkdir -p HOST_SUPERVISOR_LOG_DIR

start() {
    stop
    delete
    echo "Starting ${CONTAINER_NAME}."
    if [ ! -z "$REGISTRY" ]; then
        set -x
        docker pull $REGISTRY/$CONSUL_IMG:$IMAGE_TAG 2>&1 > /dev/null
        docker tag -f $REGISTRY/$CONSUL_IMG:$IMAGE_TAG $CONSUL_IMG 
        set +x
    fi
    # Start the consul agent
    set -x
    docker run -d \
        --restart=always \
        --net=host \
        -e GOMAXPROCS=4 \
        -v ${HOST_SUPERVISOR_LOG_DIR}:${CONTAINER_SUPERVISOR_LOG_DIR} \
        -v /var/consul:/data \
        -v /var/log/containers/consul:/var/log/containers/consul \
        -p $BRIDGE_IP:53:53 \
        -p $BRIDGE_IP:53:53/udp \
        --name $CONTAINER_NAME \
        $CONSUL_IMG \
        $JOINS \
        -rejoin \
        $RECURSORS \
        -node $NODE
    set +x
}

stop() {
    echo -n "Stopping container: "
    docker stop ${CONTAINER_NAME}
}

delete() {
    echo -n "Removing container: "
    docker rm ${CONTAINER_NAME}
}

case $1 in
    start)
        start
        ;;

   stop)
        stop
        ;;
   delete)
        delete
        ;;
   *)
        echo $USAGE
        exit 1
        ;;
esac
