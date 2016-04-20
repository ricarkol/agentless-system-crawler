#!/bin/sh

prefix=$1
target="/etc/passwd"

if [ -f ${prefix}${target} ]
then
    if [ `cat ${prefix}${target} | awk -F":" '{print $3}' | sort -n | wc -l` -eq `cat ${prefix}${target} | awk -F":" '{print $3}' | sort -nu | wc -l` ]
    then
            strResult="true"
            strReason="All UIDs are used only once."
    else
            strReason="Detected some UIDs being used more than once in ${target}"
            strResult="false"
            #cat ${prefix}${target} | awk -F":" '{print $3}' | sort -n | awk '{if (NR == 1) prevuid=$0+0; else if ($0+0 == prevuid) {prevuid=$0+0; print $0} else  prevuid=$0+0;}' | sort -nu > ${prefix}/tmp/uids.$$
            #for i in `cat ${prefix}/tmp/uids.$$`
            #do
            #    export i
            #    cat ${prefix}${target} | awk -F":" '{if ($3+0 == ENVIRON["i"]+0) printf "%-15s - %-s\n",$1,$5}' >> ${prefix}/tmp/q1_1.$$
            #done
            #cat ${prefix}/tmp/q1_1.$$ 
            #rm -f /tmp/uids.$$ /tmp/q1_1.$$
    fi
else
    strResult="false"
    strReason="File ${target} missing."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
