#!/bin/bash
# Deploys a Crawler to gather process, connection, and metric data at 5 min intervals
if [ "$1" == "--help" ] || [ "$1" == "-h" ] || [ $# == 0 ]
then 
    echo "Usage $0 url=URL [namespace=namespace]"
    echo "Example 1: Usage $0 url=http://192.67.35.89:8080/broker/v0/data?origin=com.ibm.research.crawler"
    echo "Example 2: Usage $0 url=http://192.67.35.89:8080/broker/v0/data?origin=com.ibm.research.crawler namespace=xyz"
    echo "Example 3: Usage $0 url=http://192.67.35.89:8080/broker/v0/data?origin=com.ibm.research.crawler url=kafka://host:port namespace=xyz"
    echo "Example 4: Usage $0 url=http://192.67.35.89:8080/broker/v0/data?origin=com.ibm.research.crawler format=graphite"
    echo "Example 5: Usage $0 url=http://192.67.35.89:8080/broker/v0/data?origin=com.ibm.research.crawler crawlContainers=ALL"
    echo "Example 6: Usage $0 url=file://local mode=OUTVM vmDomain=ALL"
    echo "Example 7: Usage $0 url=file://local mode=OUTVM vmDomain=instance-00000172,x86_64,3.3.3 vmDomain=instance-00000173,x86_64,2.6.5"
    echo "Example 8: Usage $0 url=file://local mode=OUTVM vmDomain=instance-00000172 vmDomain=instance-00000173"
    echo "Example 9: Usage $0 url=http://192.67.35.89:8080/broker/v0/data?origin=com.ibm.research.crawler crawlContainers=ALL environment=alchemy"
    echo "Example 10: Usage $0 url=kafka://10.114.102.216:9092/kafka-topic crawlContainers=ALL"
    exit 0
fi

NAMESPACE=
URLS=
FORMAT=csv
CONTAINERS=
MODE=INVM
VMS=
ENV=cloudsight
LOGFILE="crawler.log"

for i in $*
do
    if  [[ $i == namespace=* ]] ;
    then 
        NAMESPACE=`echo $i | cut -d'=' -f2 `
    fi
    if  [[ $i == url=* ]] ;
    then 
        URLS="$URLS `echo $i| cut -d'=' -f2`"
    fi
    if  [[ $i == format=* ]] ;
    then 
        FORMAT=`echo $i | cut -d'=' -f2`
    fi
    if  [[ $i == crawlContainers=* ]] ;
    then 
        CONTAINERS=`echo $i | cut -d'=' -f2`
    fi
    if  [[ $i == vmDomain=* ]] ;
    then 
        VMS="$VMS `echo $i| cut -d'=' -f2`"
    fi
    if  [[ $i == mode=* ]] ;
    then 
        MODE=`echo $i | cut -d'=' -f2`
    fi
    if  [[ $i == environment=* ]] ;
    then 
        ENV=`echo $i | cut -d'=' -f2`
    fi
    if  [[ $i == logfile=* ]] ;
    then 
        LOGFILE=`echo $i | cut -d'=' -f2`
    fi
done

echo mode=$MODE
echo namespace=$NAMESPACE
echo URLs=$URLS
echo format=$FORMAT
echo crawlContainers=$CONTAINERS
echo vmdomains=$VMS
echo env=$ENV

#FEATURES=os,disk,process,connection,metric,memory,cpu,load,interface
FEATURES=os,disk,process,package,connection,metric,memory,cpu,load,interface
FREQUENCY=1
#SINCE=LASTSNAPSHOT
SINCE=EPOCH

echo "Starting crawler data collector"
/usr/bin/python `pwd`/crawler.py \
        --environment $ENV --crawlmode $MODE --vmDomains $VMS \
	--crawlContainers $CONTAINERS --format $FORMAT --url $URLS \
	--namespace $NAMESPACE --since $SINCE --features $FEATURES \
	--frequency $FREQUENCY --linkContainerLogFiles --compress false --options "{\"connection\": {}, \"file\": {\"exclude_dirs\": [\"boot\", \"dev\", \"proc\", \"sys\", \"mnt\", \"tmp\", \"var/cache\", \"usr/share/man\", \"usr/share/doc\", \"usr/share/mime\"], \"root_dir\": \"/\"}, \"package\": {}, \"process\": {}, \"config\": {\"exclude_dirs\": [\"dev\", \"proc\", \"mnt\", \"tmp\", \"var/cache\", \"usr/share/man\", \"usr/share/doc\", \"usr/share/mime\"], \"known_config_files\": [\"etc/passwd\", \"etc/hosts\", \"etc/mtab\", \"etc/group\", \"vagrant/vagrantfile\", \"vagrant/Vagrantfile\"], \"discover_config_files\": true, \"root_dir\": \"/\"}, \"metric\": {}, \"disk\": {}, \"os\": {}}"&

# Store the PID for stop to know what process to kill.
PID=$!
echo $PID
echo $PID > crawler.pid
