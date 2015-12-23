#!/bin/bash

TMP_DIR=${TMP_DIR:-/tmp}
CS_LOG_ROOT=/opt/cloudsight/logcrawler
CRAWLER_DEB=crawler_1.22-alchemy-crawler_amd64.deb
LOG_CRAWLER_DEB=logcrawler_1.13-alchemylogcrawler_amd64.deb
CRAWLER_LOGS_MONITOR_DEB=crawler-logs-monitor_1.4_amd64.deb
LOGMET_TESTER_DEB=alchemylogmettester_0.4-alchemylogmettester_amd64.deb
DOWNLOADS_DIR=/root/Downloads/
LOGSTASH=logstash-1.4.2
LOGSTASH_ROOT=/opt/cloudsight-logstash
LOGS_MONITOR_ROOT=/opt/cloudsight/crawler_logs_monitor
PACKAGES_DIR=/root/research/cloudsight-container/packaging/

# LOGSTASH
#CRAWLER_EMIT_URL=mtgraphite://metrics.opvis.bluemix.net:9095/Crawler:oLYMLA7ogscT
#CRAWLER_EMIT_URL=mtgraphite://metrics.stage1.opvis.bluemix.net:9095/Crawler:5KilGEQ9qExi
CRAWLER_EMIT_URL=mtgraphite://metrics.eu-gb.opvis.bluemix.net:9095/Crawler:oS1z4EpVsQQQ
CRAWLER_LOGMET_HOST=logs.opvis.bluemix.net
CRAWLER_LOGMET_PORT=9091
CRAWLER_SUPERTENANT_ID=Crawler
CRAWLER_SUPERTENANT_PASSWORD=oLYMLA7ogscT

pushd .

cd /tmp

    sudo stop alchemy-crawler || echo "Could not stop the crawler"
    sudo stop alchemy-logcrawler || echo "Could not stop the log crawler"
    sudo stop crawler-logs-monitor || echo "Could not stop the logs monitor"
    sudo stop alchemy-logmet-tester || echo "Could not stop the logmet tester"

    sudo apt-get -y remove --purge crawler
    sudo apt-get -y remove --purge logcrawler
    sudo apt-get -y remove --purge crawler-logs-monitor
    sudo apt-get -y remove --purge alchemylogmettester

    # XXX brute force, we really need this thing to be removed and-crawler
    # package_uninstall is not doing it for some reason
    sudo dpkg -r crawler || true
    sudo dpkg -r logcrawler || true
    sudo dpkg -r crawler-logs-monitor || true
    sudo dpkg -r alchemylogmettester || true
    sudo rm -rf ${CS_LOG_ROOT} || echo "Could not delete ${CS_LOG_ROOT}"
    sudo rm -rf ${LOGS_MONITOR_ROOT} || echo "Could not delete ${LOGS_MONITOR_ROOT}"
    sudo rm -f /opt/cloudsight/alchemy-logmet-tester.py || echo "Could not delete the logmet tester script"

sudo dpkg -i ${PACKAGES_DIR}/${CRAWLER_DEB}
sudo dpkg -i ${PACKAGES_DIR}/${LOG_CRAWLER_DEB}
sudo dpkg -i ${PACKAGES_DIR}/${CRAWLER_LOGS_MONITOR_DEB}
sudo dpkg -i ${PACKAGES_DIR}/${LOGMET_TESTER_DEB}

# un-package logstash
cp ${DOWNLOADS_DIR}/${LOGSTASH}.tar.gz $TMP_DIR
tar -xzf ${TMP_DIR}/${LOGSTASH}.tar.gz
sudo rm -rf ${LOGSTASH_ROOT}
sudo mv ${TMP_DIR}/${LOGSTASH} ${LOGSTASH_ROOT}

# this would be installed by the crawler package
mkdir -p /opt/cloudsight/logcrawler/logstash_home

# install the mtlumberjack gem
sudo chown -R root.root ${LOGSTASH_ROOT}
sudo cp ${CS_LOG_ROOT}/logstash_plugins/outputs/mtlumberjack.rb ${LOGSTASH_ROOT}/lib/logstash/outputs/.
sudo mkdir -p ${LOGSTASH_ROOT}/lib/logstash/filters
sudo cp ${CS_LOG_ROOT}/logstash_plugins/filters/log_crawler_core.rb ${LOGSTASH_ROOT}/lib/logstash/filters/.
sudo bash -c 'cd '${LOGSTASH_ROOT}'; GEM_HOME=vendor/bundle/jruby/1.9 GEM_PATH= java -jar vendor/jar/jruby-complete-1.7.11.jar --1.9 -S gem install /opt/cloudsight/logcrawler/mtlumberjack-gem/mtlumberjack-0.0.20.gem;'

# copy the mtgraphite plugin from the logs_monitor package
sudo cp ${LOGS_MONITOR_ROOT}/mtgraphite.rb ${LOGSTASH_ROOT}/lib/logstash/outputs/.

popd

# Configure the service
sudo sed -i s"/<LOGMET_HOST>/${CRAWLER_LOGMET_HOST}/" /opt/cloudsight/logcrawler/logstash_alchemylogcrawler.conf
sudo sed -i s"/<LOGMET_PORT>/${CRAWLER_LOGMET_PORT}/" /opt/cloudsight/logcrawler/logstash_alchemylogcrawler.conf
sudo sed -i s"/<SUPERTENANT_ID>/${CRAWLER_SUPERTENANT_ID}/" /opt/cloudsight/logcrawler/logstash_alchemylogcrawler.conf
sudo sed -i s"/<SUPERTENANT_PASSWORD>/${CRAWLER_SUPERTENANT_PASSWORD}/" /opt/cloudsight/logcrawler/logstash_alchemylogcrawler.conf

# Configure the logs monitor service
CRAWLER_MET_PORT=9095
CRAWLER_MET_HOST=`echo ${CRAWLER_EMIT_URL} | sed -e's,^mtgraphite://\(.*\):9095.*,\1,g'`
CRAWLER_SUPERTENANT_ID=`echo ${CRAWLER_EMIT_URL} | sed -e's,^mtgraphite://.*:9095/\(.*\):.*,\1,g'`
CRAWLER_SUPERTENANT_PASSWORD=`echo ${CRAWLER_EMIT_URL} | awk -F: '{print $NF}'`
if [ "${CRAWLER_EMIT_URL#*stage}" != "$CRAWLER_EMIT_URL" ]
then
        # stage (Ricardo Koller's space)
        SPACE_ID=25aa4c07-4a76-43ba-af53-81af7d1733a9
else
	if [ "${CRAWLER_EMIT_URL#*eu-gb}" != "$CRAWLER_EMIT_URL" ]
	then
	        # prod lon02 (Test Alchemy-test space)
        	SPACE_ID=2c1c93ec-dbf9-43ef-a2da-cb6759258275.eu-gb
	else
	        # prod dal09 (Test Alchemy-test space)
        	SPACE_ID=1fb90c5d-84e6-452f-a131-9128c565a64f
	fi
fi
sudo sed -i s"/<LOGMET_HOST>/${CRAWLER_MET_HOST}/" /opt/cloudsight/crawler_logs_monitor/logstash_crawler_logs_monitor.conf
sudo sed -i s"/<LOGMET_PORT>/${CRAWLER_MET_PORT}/" /opt/cloudsight/crawler_logs_monitor/logstash_crawler_logs_monitor.conf
sudo sed -i s"/<SUPERTENANT_ID>/${CRAWLER_SUPERTENANT_ID}/" /opt/cloudsight/crawler_logs_monitor/logstash_crawler_logs_monitor.conf
sudo sed -i s"/<SUPERTENANT_PASSWORD>/${CRAWLER_SUPERTENANT_PASSWORD}/" /opt/cloudsight/crawler_logs_monitor/logstash_crawler_logs_monitor.conf
sudo sed -i s"/<SPACE_ID>/${SPACE_ID}/" /opt/cloudsight/crawler_logs_monitor/logstash_crawler_logs_monitor.conf

# Config the logmet tester
sudo bash -c "echo \"env URL=${CRAWLER_EMIT_URL}\" >> /etc/init/alchemy-logmet-tester.conf"

exit 0
