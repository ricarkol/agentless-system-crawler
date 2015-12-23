#!/bin/bash

echo "#!/bin/bash " >  /opt/timemachine/start-timemachine-in-docker.sh
echo "/opt/timemachine/timemachine -v $*" >> /opt/timemachine/start-timemachine-in-docker.sh
chmod 755 /opt/timemachine/start-timemachine-in-docker.sh

service supervisor start
echo "Start script waiting for SIGTERM."
trap "echo Got SIGTERM. Goodbye!; exit" SIGTERM
tail -f /dev/null &
wait
