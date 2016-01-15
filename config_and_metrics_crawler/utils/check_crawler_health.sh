#!/bin/bash

KEY="/Users/canturk/keys/vizio_canturk.key"
#KEY="/root/keys/vizio_canturk.key" #for host-04
USR="thor"
PERIOD=600 #[s]
SSH_TIMEOUT=3 #[3]
red='\e[0;31m'
pink='\e[1;31m'
green='\e[0;32m'
yellow='\e[0;33m'
blue='\e[0;34m'
endColor='\e[0m'

SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=${SSH_TIMEOUT}"

#function: $1: Host IP
check_status () {
    resp=`ssh -q -i $KEY $SSH_OPTIONS ${USR}@$1 "hostname; status alchemy-crawler" 2> "./check_crawler_health.errlog"` 
    name=`echo "$resp" | sed -n 1p`
    stat=`echo "$resp" | sed -n 2p`
    shortname=`echo "$name" | cut -c 1-20 `
    shortstat=`echo "$stat" | cut -c 1-50 `
    if [[ $stat == *"running"* ]]; then
        printf "%-20s | %-15s | ${green}%-50s${endColor}\n" "$shortname" "$1" "$shortstat"
    elif [ -z "${name}" ]; then #empty name means, no hostname, assume ssh timed out
        printf "%-20s | %-15s | ${yellow}%-50s${endColor}\n" " -- " "$1" "ssh connection failed!"
    else
        printf "${red}%-20s | %-15s | %-50s${endColor}\n" "$shortname" "$1" "$shortstat"
    fi
}

#Main:
for i in {0..288}
do 
    printf " \n"
    printf "${pink}Alchemy Crawler Healthcheck #${i}: `date "+%Y%m%d_%H%M%S"`${endColor}\n"
    printf "${pink}======================================================================================== ${endColor}\n"

    printf "${yellow}Prod 1:${endColor}\n"
    printf "${yellow}%s${endColor}\n" "----------------------------------------------------------------------------------------"
    printf "%-20s | %-15s | %-50s\n" "Host" "IP" "Status"
    printf "%s\n" "----------------------------------------------------------------------------------------"
    for ip in  10.120.108.20 10.120.108.28 10.120.108.12 10.120.108.14 10.120.108.18 10.120.108.16 \
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
