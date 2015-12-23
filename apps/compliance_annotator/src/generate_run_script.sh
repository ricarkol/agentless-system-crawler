#!/bin/bash

echo "#!/bin/bash " >  /var/www/html/run_scanner.sh
echo "/var/www/html/compliance_scanner.py $*" >> /var/www/html/run_scanner.sh
chmod 755 /var/www/html/compliance_scanner.py
chmod 755  /var/www/html/run_scanner.sh

cd /var/www/html
./run_scanner.sh

#echo "#!/bin/bash " >  /var/www/html/run_reporter.sh
#echo "/var/www/html/run_update_report.sh $*" >> /var/www/html/run_reporter.sh
#chmod 755 /var/www/html/run_update_report.sh
#chmod 755  /var/www/html/run_reporter.sh
#
#
#service supervisor start
#echo "Start script waiting for SIGTERM."
#trap "echo Got SIGTERM. Goodbye!; exit" SIGTERM
#tail -f /dev/null &
#wait
