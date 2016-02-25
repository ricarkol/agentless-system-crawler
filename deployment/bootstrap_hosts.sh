#!/bin/bash 

#
# Vulnerability Advisor host bootstrapping
# (c) IBM Research 2015
#

if [ $# -eq 1 ]
   then
   echo "------------------------------------------------"
   echo "Bootstrapping the designated environment:" $1
   ENV=$1
   TARGET_HOST=
elif [ $# -eq 2 ]
   then
   echo "------------------------------------------------"
   echo "Bootstrapping:" $2 "only, in environment:" $1
   ENV=$1
   TARGET_HOST=$2
else
   echo "Usage: $0 <ENV> [<TARGET_HOST>]"
   exit 1
fi

. ../config/hosts.${ENV}
. ../config/storage_devices.${ENV}

SCP="scp -o StrictHostKeyChecking=no"
SSH="ssh -o StrictHostKeyChecking=no"

if [ "$TARGET_HOST" != "" ]
   then
   HOSTS_LINE=`grep "HOSTS=(" ../config/hosts.${ENV}`
   HOSTS_ARRAY=$(echo $HOSTS_LINE | sed -e 's/\$//g' -e 's/HOSTS=(//g' -e 's/)//' -e 's/\s\+/\n/g')
   arrIN=(${HOSTS_ARRAY// / })

   if ! [[ "${arrIN[*]}" =~ "$TARGET_HOST" ]]
      then
         echo "------------------------------------------------"
         echo "This does not exist in $ENV, please choose one of the following to bootstrap:"
         echo "${arrIN[@]}"
      exit 1
   else
      echo "The host $TARGET_HOST has the IP ${!TARGET_HOST}"
   fi
fi

PARTITION_NUMBER=1
for host in ${!DOCKER_DEVICES[@]}
   do
   DEVICE=${DOCKER_DEVICES[$host]}

   if [ "$TARGET_HOST" != "" ]
      then
      if [ "${!TARGET_HOST}" != "$host" ]
         then
         continue
      fi
   else
      echo "TARGET_HOST = $host"
   fi

   echo ""
   echo "================================================"
   echo "BOOTSTRAPPING $host"
   echo ""
   echo "-------------DOCKER_DEVICES---------------------"
   echo "Initial block devices in host $host"
   $SCP utils/probe_disks.sh ${SSH_USER}@$host:probe_disks.sh
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo ./probe_disks.sh
   $SCP ${SSH_USER}@$host:/tmp/partitions.txt $host.partitions
   cat $host.partitions

   echo "------------------------------------------------"
   echo "Creating docker partition on host $host at device $DEVICE"
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/sbin/service docker stop
   
   $SCP utils/create_partition.sh ${SSH_USER}@$host:create_partition.sh
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo ./create_partition.sh $DEVICE $DOCKER_PARTITION_START $DOCKER_PARTITION_END $PARTITION_NUMBER $DOCKER_PARTITION_FSTYPE $DOCKER_PARTITION_MOUNTPOINT

   STAT=$?
   if [ $STAT -eq 0 ] 
   then
       $SCP ../config/docker.config.${ENV} ${SSH_USER}@$host:/tmp/docker
       $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/mv /tmp/docker /etc/default/docker
   fi

   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/sbin/service docker start
   
   echo "------------------------------------------------"
   echo "Final block devices in host $host"
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo ./probe_disks.sh
   $SCP ${SSH_USER}@$host:/tmp/partitions.txt $host.partitions
   cat $host.partitions

   if [ $STAT -ne 0 ] 
   then 
       echo "Docker partition creation failed for $host with $STAT, exiting"
       exit 1
   fi
done


PARTITION_NUMBER=1
for host in ${!DOCKER_DEVICES_LARGE[@]}
   do
   DEVICE=${DOCKER_DEVICES_LARGE[$host]}

   if [ "$TARGET_HOST" != "" ]
      then
      if [ "${!TARGET_HOST}" != "$host" ]
         then
         continue
      fi
   else
      echo "TARGET_HOST = $host"
   fi
  
   echo "-------------DOCKER_DEVICES_LARGE---------------"
   echo "Initial block devices in host $host"
   $SCP utils/probe_disks.sh ${SSH_USER}@$host:probe_disks.sh
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo ./probe_disks.sh
   $SCP ${SSH_USER}@$host:/tmp/partitions.txt $host.partitions
   cat $host.partitions

   echo "------------------------------------------------"
   echo "Creating docker partition on host $host at device $DEVICE"
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/sbin/service docker stop
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm /etc/default/docker
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/apt-get -y install lxc-docker
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/sbin/service docker stop
   $SCP ../config/docker.config.${ENV} ${SSH_USER}@$host:/tmp/docker
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/mv /tmp/docker /etc/default/docker

   $SCP utils/create_partition.sh ${SSH_USER}@$host:create_partition.sh
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo ./create_partition.sh $DEVICE $DOCKER_PARTITION_START $DOCKER_PARTITION_LARGE_END $PARTITION_NUMBER $DOCKER_PARTITION_FSTYPE $DOCKER_PARTITION_MOUNTPOINT 

   STAT=$?

   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/sbin/service docker start
   
   echo "------------------------------------------------"
   echo "Final block devices in host $host"
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo ./probe_disks.sh
   $SCP ${SSH_USER}@$host:/tmp/partitions.txt $host.partitions
   cat $host.partitions

   if [ $STAT -ne 0 ] 
   then 
       echo "Docker partition creation failed for $host with $STAT, exiting"
       exit 1
   fi
done

PARTITION_NUMBER=2
for host in ${!DATA_DEVICES[@]}
   do
   DEVICE=${DATA_DEVICES[$host]}

   if [ "$TARGET_HOST" != "" ]
      then
      if [ "${!TARGET_HOST}" != "$host" ]
         then
         continue
      fi
   else
      echo "TARGET_HOST = $host"
   fi

   echo "-------------DATA_DEVICES-----------------------"
   echo "Initial block devices in host $host"
   $SCP utils/probe_disks.sh ${SSH_USER}@$host:probe_disks.sh
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo ./probe_disks.sh
   $SCP ${SSH_USER}@$host:/tmp/partitions.txt $host.partitions
   cat $host.partitions

   echo "------------------------------------------------"
   echo "Creating data partition on host $host at device $DEVICE"
   $SCP utils/create_partition.sh ${SSH_USER}@$host:create_partition.sh
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo ./create_partition.sh $DEVICE $DATA_PARTITION_START $DATA_PARTITION_END $PARTITION_NUMBER $DATA_PARTITION_FSTYPE $DATA_PARTITION_MOUNTPOINT

   STAT=$?

   echo "------------------------------------------------"
   echo "Final block devices in host $host"
   $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo ./probe_disks.sh
   $SCP ${SSH_USER}@$host:/tmp/partitions.txt $host.partitions
   cat $host.partitions
   if [ $STAT -ne 0 ] 
   then 
       echo "Data partition creation failed for $host with $STAT, exiting"
       exit 1
   fi
done
