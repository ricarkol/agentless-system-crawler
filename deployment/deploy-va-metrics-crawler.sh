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



if [ "$ENABLE_VA_CRAWLER" = "true" ] 
then
    for host in ${HOSTS[@]}
    do

	# XXX uncomment to avoid installing crawlers on regcrawl VMs
	#if [ $host == $REGCRAWL1 ] || [ $host == $REGCRAWL2 ] || [ $host == $REGCRAWL3 ]
        #then
        #    echo "Skipping va-crawler installation on regcrawler $host"
        #    continue
        #fi

        echo "Installing va-crawler on host $host"

        # jsut to check what's running there
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo docker ps

	    #this is a XXX hack. Forgot to change alchemy-crawler to vacrawler in the pre-removal fpm script
        #$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo cp /etc/init/va-crawler.conf /etc/init/alchemy-crawler.conf
        #$SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service alchemy-crawler "start"

        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service va-crawler-host "stop" || true
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service va-crawler-containers "stop" || true

        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /bin/rm -rf /opt/cloudsight/va-crawler

        echo "Starting va-crawler on host $host"
        config_file=crawler-config.sh
        echo "env SPACE_ID=$VA_CRAWLER_SPACE_ID" >$config_file
        echo "env CLOUDSIGHT_CRAWL_EMIT_URL=$VA_CRAWLER_EMIT_URL" >>$config_file

        #upstart config file
        upstart_config_file_containers=/etc/init/va-crawler-containers.conf
        upstart_config_file_host=/etc/init/va-crawler-host.conf

        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mkdir -p $cloudsight_scripts_dir/config
        $SCP ../packaging/created_packages/crawler/$VACRAWLER_DEB_FILE ${SSH_USER}@$host:$VACRAWLER_DEB_FILE
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/apt-get update --fix-missing
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/apt-get install -y --fix-missing  make python2.7 python-pip gcc python-dev rpm uuid
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/apt-get -f install

        echo "installed vacrawler dependencies"
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -i $VACRAWLER_DEB_FILE || echo "Could not install va-crawler package"
        echo "installed package"
        # $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/dpkg -l
        # We copy the config file just for auditing purposes
        $SCP $config_file ${SSH_USER}@$host:$config_file
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv $config_file $cloudsight_scripts_dir/config/$config_file

        # XXX consider using the $config_file instead of changing the upstart config file
        $SSH ${SSH_USER}@$host HOST=$host "/usr/bin/sudo cat ${upstart_config_file_containers} $cloudsight_scripts_dir/config/$config_file > /tmp/va-crawler.conf"
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv /tmp/va-crawler.conf ${upstart_config_file_containers} || true
        $SSH ${SSH_USER}@$host HOST=$host "/usr/bin/sudo cat ${upstart_config_file_host} $cloudsight_scripts_dir/config/$config_file > /tmp/va-crawler.conf"
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo mv /tmp/va-crawler.conf ${upstart_config_file_host} || true

        cat ../collector/crawler/requirements.txt > /tmp/crawler_requirements.txt
        # Keeping in in case we need to backtrack backtrack backtrack if we break dev
        # $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo pip install --no-index --find-links="/opt/cloudsight/python_packages/" psutil bottle requests simplejson pydoubles netifaces kafka-python docker-py

        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo pip install -r /tmp/crawler_requirements.txt  || true
	    echo "Installed pip packages"
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service va-crawler-host "start" || true
        $SSH ${SSH_USER}@$host HOST=$host /usr/bin/sudo /usr/bin/service va-crawler-containers "start" || true


        STAT=$?
        if [ $STAT -ne 0 ]
        then
            echo "Failed to start va-crawler in $host"
            exit 1
        fi

    done
fi
