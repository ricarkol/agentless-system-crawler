#!/bin/bash

echo "#!/bin/bash " >  /opt/usncrawler/run_usncrawler.sh 
echo "/opt/usncrawler/usncrawler.py $*" >> /opt/usncrawler/run_usncrawler.sh
chmod 755  /opt/usncrawler/run_usncrawler.sh

service supervisor start
echo "Start script waiting for SIGTERM."
trap "echo Got SIGTERM. Goodbye!; exit" SIGTERM
tail -f /dev/null &
wait


