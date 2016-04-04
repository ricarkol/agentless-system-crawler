#Script to emit artificial logdata for scale-testing
#pip install jinja2 # we moved it to install.sh

BROKERIP=$1 #"108.168.238.118" 
BROKERPORT=$2 #8081
SYSTEMPREFIX=$3 #"scaletestinglaptop03"
EVENTRATE=$4 #1 # 1/sec
EVENTVOLUME=$5 #1 # size of each eventline in KB
NUMLOGFILES=$6 #100 # number of log files to crawl

LOGSTASH_DIR="/opt/logstash"
BASE_DIR=/vagrant/collector/log_crawler/scaletesting/
GENERATED_LOGDATAFILE=$BASE_DIR/SCALETESTING_LOGDATA.log
GENERATED_YMLFILE=$BASE_DIR/SCALETESTING_LOGCRAWLERCONFIG.yml
LOGFILESCRAWL_DIR=$BASE_DIR/logfilesbeingcrawled/
LOG_CRAWLER_DIR=/vagrant/collector/log_crawler/
LS_CONFIG_TEMPLATE=$LOG_CRAWLER_DIR/conf/shipper.conf.tenjin


cd $BASE_DIR

# start the synthetic logdata generator
echo ">>> Running the synthetic logdata generator"
pkill -f '\-\-logdatafile' # kill previously running instance if any
rm $GENERATED_LOGDATAFILE* # kill previous log, including rotating versions of this log
nohup python generateLogdata.py --event-rate $EVENTRATE --event-volume $EVENTVOLUME --logdatafile $GENERATED_LOGDATAFILE &

# create a directory with the desired number of logfile SOFTLINKED to GENERATED_LOGDATAFILE
mkdir -p $LOGFILESCRAWL_DIR
echo ">>> Deleting previously created logs in $LOGFILESCRAWL_DIR"
rm $LOGFILESCRAWL_DIR/*.log

# create soft-links to the generated logdata
echo ">>> Create the desired number of logfiles being crawled by soft-linking to the generated logdata file"
for ((i = 0 ; i < $NUMLOGFILES ; i++ ))
do
	ln -s $GENERATED_LOGDATAFILE $LOGFILESCRAWL_DIR/scaletesting.$i.log
done


# Create a synthetically generated .yml file containing the desired number of logfiles being crawled 
echo ">>> Create a synthetically generated log_crawler config_file (.yml) file"
python generateYmlfile.py --logcrawldir $LOGFILESCRAWL_DIR --numlogfiles $NUMLOGFILES --broker-host $BROKERIP --broker-port $BROKERPORT --ymlfilename $GENERATED_YMLFILE --system-prefix $SYSTEMPREFIX --batch-events 1 --batch-timeout 1  


# Use the logcrawler script (config_shipper.py) to convert our generated ymlfile to the desired logstash config file (i.e. /opt/logstash/shipper.conf) and then start logstash
echo "Creating the logstash config file from our generated ymlfile" 
python $LOG_CRAWLER_DIR/config_shipper.py $GENERATED_YMLFILE $LS_CONFIG_TEMPLATE  >$LOGSTASH_DIR/shipper.conf
echo "Starting logstash with the logstash config file"
pkill -f shipper.conf
nohup $LOGSTASH_DIR/bin/logstash -f $LOGSTASH_DIR/shipper.conf --pluginpath $LOG_CRAWLER_DIR >/var/log/shipper.log 2>&1 &

