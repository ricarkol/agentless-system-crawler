#/bin/bash

# Only run as root (or with sudo)
if [ "$(id -u)" != "0" ]; then
	echo "Sorry, you are not root."
	exit 1
fi

KAFKA_HOSTNAME="kafka-cs.sl.cloud9.ibm.com"

# Pushes a dummy frame non stop
echo "Pres CTRL+C to stop..."

while :
do
	# Clean the notification kafka producer log so we can easily count the
	# number of retries.  In this case there are no crawler logs, so we
	# just need to check for the kafka-producer logs.
	rm -f /var/log/kafka-producer.log

	bash crawl_docker_dummy_image.sh dummy-ubuntu-frame.0 \
		kafka://${KAFKA_HOSTNAME}:9092/config	\
		kafka://${KAFKA_HOSTNAME}:9092/notification \
		`uuid` `uuid` `uuid` `uuid` `uuid`

	# XXX just print the number of retries
	grep -c Retry /var/log/kafka-producer.log
done
