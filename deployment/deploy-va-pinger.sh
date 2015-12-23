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

DEST_ADDRS=`echo ${HOSTS[@]} | sed -e 's/ /,/g'`

if [ "$ENABLE_VA_CRAWLER" = "true" ] 
then
    for host in ${HOSTS[@]}
    do

	# TODO we skip the regcrawlers for now. The TODO is to change the
	# regcrawl package to not install crawlers, and instead depend on teh
	# crawler package
        #if [ $host == $REGCRAWL1 ] || [ $host == $REGCRAWL2 ] || [ $host == $REGCRAWL3 ]
        #then
        #    echo "Skipping va-pinger installation on regcrawler $host"
        #    continue
        #fi

        #if ! [ $host == $REGCRAWL2 ] && ! [ $host == $REGCRAWL1 ]
        #then
        #    echo "Skipping va-pinger installation on regcrawler $host"
        #    continue
        #fi

        echo "Stopping va-pinger on host $host"
	$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service va-pinger "stop" || true
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -r vapinger || true
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg --purge vapinger || true
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm -rf /opt/cloudsight/va-pinger
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm -f /etc/init/va-pinger.conf

        echo "Starting va-pinger on host $host"
	config_file=${VACRAWLER}.sh
	echo "env SPACE_ID=$VA_CRAWLER_SPACE_ID" >>$config_file
	echo "env CLOUDSIGHT_CRAWL_EMIT_URL=$VA_CRAWLER_EMIT_URL" >>$config_file
	echo "env DEST_ADDRS=$DEST_ADDRS" >>$config_file
	#upstart config file
	upstart_config_file=/etc/init/va-pinger.conf

	package=vapinger_0.1-va-pinger_amd64.deb

	$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
	$SCP ../packaging/created_packages/vapinger/$package ${SSH_USER}@$host:$package
	$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/apt-get update --fix-missing
	$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/apt-get install -y --fix-missing  make python2.7 python-pip gcc python-dev rpm uuid
	echo "installed vapinger dependencies"
	$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -i $package
	# We copy the config file just for auditing purposes
	$SCP $config_file ${SSH_USER}@$host:$config_file
	$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file
	# XXX consider using the $config_file instead of changing the upstart config file
	$SSH ${SSH_USER}@$host HOST=$host "/usr/bin/sudo cat ${upstart_config_file} $cloudsight_scripts_dir/config/$config_file > /tmp/va-pinger.conf"
	$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv /tmp/va-pinger.conf ${upstart_config_file}
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo pip install --no-index --find-links="/opt/cloudsight/va-pinger/python_packages/" psutil bottle requests simplejson pydoubles netifaces kafka-python docker-py pykafka
	$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service va-pinger start

        STAT=$?
        if [ $STAT -ne 0 ]
        then
            echo "Failed to start va-pinger in $host"
            exit 1
        fi

    done
fi
