#!/bin/bash


#
# Vulnerability Advisor logstash-forwarder
# (c) IBM Research 2015
#

if [ $# -ne 1 ] ; then
   echo "Usage: $0 <ENV>"
   exit 1
fi


ENV=$1

. ../config/hosts.${ENV}
. ../config/component_configs.sh

SCP="scp -o StrictHostKeyChecking=no"
SSH="ssh -o StrictHostKeyChecking=no"


#starting up mt-logstash-forwarders
if [ "$ENABLE_LOGSTASH_FORWARDER" = "true" ] 
    then
    for host in ${HOSTS[@]}
        do
        echo "Stopping mt-logstash-forwarder on host $host"
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service mt-logstash-forwarder stop
        dpkg -r mt-logstash-forwarder 

        #$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm -r /var/log/cloudsight
        #$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm /var/log/mt-logstash-forwarder.log 

        echo "Starting mt-logstash-forwarder on host $host"
        config_file=mt-lsf-config.sh
        echo "LSF_INSTANCE_ID=\"$host\"" >$config_file
        echo "LSF_TARGET=\"$LSF_TARGET\"" >>$config_file
        echo "LSF_TENANT_ID=\"$LSF_TENANT_ID\"" >>$config_file
        echo "LSF_PASSWORD=\"$LSF_PASSWORD\"" >>$config_file
        echo "LSF_GROUP_ID=\"$LSF_GROUP_ID\"" >>$config_file
        package_path="../../packaging/alchemy/mt-logstash-forwarder/$LOGSTASH_DEB_FILE"
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/apt-get update -y --fix-missing
        $SCP $package_path ${SSH_USER}@$host:$LOGSTASH_DEB_FILE
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -i $LOGSTASH_DEB_FILE
        $SCP $config_file ${SSH_USER}@$host:$config_file
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file /etc/mt-logstash-forwarder/
        $SCP ../packaging/alchemy/mt-logstash-forwarder/cloudsight.conf ${SSH_USER}@$host:cloudsight.conf
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv cloudsight.conf /etc/mt-logstash-forwarder/conf.d/
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service mt-logstash-forwarder start
    done
fi

if [ "$?" -eq "0" ]
    then
    echo "mt-logstash-forwader deployed." 
else
    echo "Failed mt-logstash-forwarder!"
    exit 1
fi
