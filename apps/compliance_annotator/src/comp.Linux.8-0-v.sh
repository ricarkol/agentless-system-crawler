#!/bin/sh

prefix=$1
target="/etc/sysctl.conf"

if [ -f ${prefix}${target} ]
then
    keyvalue_line=`grep ^net.ipv4.icmp_echo_ignore_broadcasts ${prefix}${target} | sed 's/=/ /g'`
    set -- $keyvalue_line
    value_part=$2
    if [ ! -z "$value_part" ] && [ $value_part -eq 1 ]
    then
        strResult="true"
        strReason="net.ipv4.icmp_echo_ignore_broadcasts is set as 1 in $target"
    else
        strResult="false"
        strReason="net.ipv4.icmp_echo_ignore_broadcasts is not 1 in $target"
    fi
else
    strResult="false"
    strReason="File $target does not exist."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
