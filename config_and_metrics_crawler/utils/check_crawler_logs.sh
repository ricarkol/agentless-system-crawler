#!/bin/bash

KEY="/Users/canturk/keys/vizio_canturk.key"
#KEY="/root/keys/vizio_canturk.key" #for host-04
USR="thor"
PERIOD=600 #[s]
SSH_TIMEOUT=3 #[3]
LOG="/var/log/crawler.log.mtgraphite"
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=${SSH_TIMEOUT}"
OP_FORMAT="tail -n 5 ${LOG}"
red='\e[0;31m'
pink='\e[1;31m'
green='\e[0;32m'
yellow='\e[0;33m'
blue='\e[0;34m'
lgray='\e[0;37m'
dgray='\e[1;30m'
white='\e[1;37m'
endColor='\e[0m'

#Cleanup function when SIGINT, etc. is received
function cleanup {
	printf "\nInterrupt received, cleaning up..."
	#kill all processes here
	printf "Done, exiting.\n"
	exit 1;
}
#Trap signals for cleanup
trap cleanup SIGHUP SIGINT SIGTERM

#function: $1: Host IP
check_status () {
    resp=`ssh -q -i $KEY $SSH_OPTIONS ${USR}@$1 "hostname; tail -n 1 $LOG; ${OP_FORMAT}" 2> "./check_crawler_logs.errlog"` 
    name=`echo "$resp" | sed -n 1p`
    lastlogline=`echo "$resp" | sed -n 2p`
    #stat=`echo "$resp" | sed -n 2,6p`
    stat=`echo "$resp" | tail -n +3`
    shortname=`echo "$name" | cut -c 1-20 `
    
    if [ -z "${name}" ]; then #empty name means, no hostname, assume ssh timed out
        printf "%-20s | %-15s | ${yellow}%-50s${endColor}\n" " -- " "$1" "ssh connection failed!"
    elif [ -z "${lastlogline}" ]; then #empty log resp. or failed tail query
        printf "%-20s | %-15s | ${red}%-50s${endColor}\n" "$shortname" "$1" "No log received for $LOG!"
    elif [ -z "${stat}" ]; then #empty log resp.
        if [ "X${format}" = "Xlast5" ]; then
            printf "%-20s | %-15s | ${red}%-50s${endColor}\n" "$shortname" "$1" "No log received for $LOG!"
        elif [ "X${format}" = "Xerror" ]; then
            printf "%-20s | %-15s | ${lgray}%-50s${endColor}\n" "$shortname" "$1" "No ERRORs received from $LOG!"
        elif [ "X${format}" = "Xwarning" ]; then
            printf "%-20s | %-15s | ${lgray}%-50s${endColor}\n" "$shortname" "$1" "No WARNINGs/ERRORs received from $LOG!"
        else 
            printf "%-20s | %-15s | ${red}%-50s${endColor}\n" "$shortname" "$1" "Unexpected format ${format}!"
        fi
    else
        printf "%-20s | %-15s | %-50s\n" "$shortname" "$1" "$LOG [last 5]:"
        while read logline; do 
            if [ -n "${logline}" ]; then # skip blank
                if [[ $logline == *"response of 1A"* ]]; then
                    printf "    ${green}%s${endColor}\n" "$logline"
                elif [[ $logline == *"WARNING"* ]]; then
                    printf "    ${pink}%s${endColor}\n" "$logline"
                elif [[ $logline == *"ERROR"* ]]; then
                    printf "    ${red}%s${endColor}\n" "$logline"
                else
                    printf "    ${dgray}%s${endColor}\n" "$logline"
                fi
            fi
        done < <(echo "$stat")
    fi
}

################################################################

#Main:
if [ $#  -lt 2 ]; then
        echo 1>&2 "Track last few lines of crawler logs."
        echo 1>&2 "Usage: $0 " 
        echo 1>&2 "          -t <Target Log> " 
        echo 1>&2 "             --> /var/log/crawler.log.mtgraphite" 
        echo 1>&2 "             --> /var/log/crawler.log" 
        echo 1>&2 "             --> /var/log/crawler_upstart.log | etc." 
        echo 1>&2 "          [-f <Output Format>"]
        echo 1>&2 "             --> last5 (default, print last 5 lines of log) " 
        echo 1>&2 "             --> error (print only errors seen in last 100 lines of log)" 
        echo 1>&2 "             --> warning (print errors + warnings seen in last 100 lines of log)" 
        echo 1>&2 "  i.e.: $0 -t crawler.log.mtgraphite -f last5"
        echo 1>&2 "        $0 -t crawler.log -f warning"
        echo 1>&2 "Output:"
        echo 1>&2 "  Just dumps to screen (tee to file at some point)"
        echo 1>&2 "Terminate $0 with CTRL-C"
        echo 1>&2 "  "
        exit 1
fi

#echo "OPTIND starts at $OPTIND"
while getopts ":t:f:" optname; do
    case "$optname" in
      "t")
        tgt_log=$OPTARG;
        #echo "Target log: $tgt_log"
        ;;
      "f")
        format=$OPTARG;
        #echo "Output format: $format";
        ;;
      "?")
        echo "Unknown option $OPTARG, skipping..."
        ;;
      ":")
        echo "An argument is required for option $OPTARG, exiting...";
        exit 1
        ;;
      *)
        echo "Unknown error while processing options, exiting...";
        exit 1
        ;;
    esac
    #echo "OPTIND is now $OPTIND"
done

if [[ -z "$tgt_log" ]]; then
	echo "target log is required (-t), exiting...";
	exit 1;
else
    LOG=$tgt_log
	echo "Target log: ${LOG}";
fi
if [[ -z "$format" ]]; then
	echo "Output format not defined, will use last 5";
    OP_FORMAT="tail -n 5 ${LOG}"
elif [ "X${format}" = "Xlast5" ] ; then
    OP_FORMAT="tail -n 5 ${LOG}"
	echo "Output format: ${format} --> Will print last 5 lines of $LOG";
elif [ "X${format}" = "Xerror" ] ; then
    OP_FORMAT="tail -n 100 ${LOG} | grep -a ERROR"
	echo "Output format: ${format} --> Will print ONLY ERRORs in the last 100 lines of $LOG";
elif [ "X${format}" = "Xwarning" ] ; then
    OP_FORMAT="tail -n 100 ${LOG} | grep -a -e ERROR -e WARNING"
	echo "Output format: ${format} --> Will print ONLY ERROR and WARNINGs in the last 100 lines of $LOG";
else
	echo "Output format: ${format} --> Unknown format, exiting...";
    exit 1;
fi

for i in {0..288}
do 
    printf " \n"
    printf "${pink}Alchemy Crawler Log Tracker #${i}: `date "+%Y%m%d_%H%M%S"`${endColor}\n"
    printf "${pink}======================================================================================== ${endColor}\n"

    printf "${yellow}Prod 1:${endColor}\n"
    printf "${yellow}%s${endColor}\n" "----------------------------------------------------------------------------------------"
    printf "%-20s | %-15s | %-50s\n" "Host" "IP" "Status"
    printf "%s\n" "----------------------------------------------------------------------------------------"
    for ip in  10.121.96.76 \
        10.120.108.20 10.120.108.28 10.120.108.12 10.120.108.14 10.120.108.18 10.120.108.16 \
               10.120.108.26 10.120.108.22 10.120.108.8 10.120.108.10 10.120.108.24
    do
        check_status $ip
    done
    printf "======================================================================================== \n"
    
    printf "${yellow}Prod 2:${endColor}\n"
    printf "${yellow}%s${endColor}\n" "----------------------------------------------------------------------------------------"
    printf "%-20s | %-15s | %-50s\n" "Host" "IP" "Status"
    printf "%s\n" "----------------------------------------------------------------------------------------"
    for ip in  10.121.96.218 10.121.96.214 10.121.96.212 10.121.96.202 10.121.96.206 10.121.96.208 \
               10.121.96.210 10.121.96.200 10.121.96.198 10.121.96.204 10.121.96.216
    do
        check_status $ip
    done
    printf "======================================================================================== \n"
    
    printf "${yellow}Prod 3:${endColor}\n"
    printf "${yellow}%s${endColor}\n" "----------------------------------------------------------------------------------------"
    printf "%-20s | %-15s | %-50s\n" "Host" "IP" "Status"
    printf "%s\n" "----------------------------------------------------------------------------------------"
    for ip in  10.121.96.154 10.121.96.152 10.121.96.138 10.121.96.140 10.121.96.136 10.121.96.142 \
               10.121.96.150 10.121.96.134 10.121.96.148 10.121.96.146 10.121.96.144 
    do
        check_status $ip
    done
    printf "======================================================================================== \n"

    printf "${yellow}Prod 4:${endColor}\n"
    printf "${yellow}%s${endColor}\n" "----------------------------------------------------------------------------------------"
    printf "%-20s | %-15s | %-50s\n" "Host" "IP" "Status"
    printf "%s\n" "----------------------------------------------------------------------------------------"
    for ip in  10.121.96.90 10.121.96.80 10.121.96.74 10.121.96.70 10.121.96.78 10.121.96.82 \
               10.121.96.72 10.121.96.88 10.121.96.86 10.121.96.84 10.121.96.76
    do
        check_status $ip
    done
    printf "======================================================================================== \n"
    
    sleep $PERIOD
done
