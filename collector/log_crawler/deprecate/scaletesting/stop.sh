# Stopping script (verify that the string constants below conform to the start script

BASE_DIR=/vagrant/collector/log_crawler/scaletesting/
GENERATED_LOGDATAFILE=$BASE_DIR/SCALETESTING_LOGDATA.log
GENERATED_YMLFILE=$BASE_DIR/SCALETESTING_LOGCRAWLERCONFIG.yml
LOGFILESCRAWL_DIR=$BASE_DIR/logfilesbeingcrawled/


pkill -f 'shipper.conf' # kill logstash
pkill -f '\-\-logdatafile' # kill previously running instance of the logdata generator if any
rm $GENERATED_LOGDATAFILE* # kill previous log, including rotating versions of this log

rm -rf $LOGFILESCRAWL_DIR
rm $GENERATED_YMLFILE
rm *.out
