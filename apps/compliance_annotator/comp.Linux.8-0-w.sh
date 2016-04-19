#!/bin/sh

prefix=$1
target="/etc/sysctl.conf"

if [ -f ${prefix}${target} ]
then
    keyvalue_line=`grep ^net.ipv4.conf.all.accept_redirects ${prefix}${target} | sed 's/=/ /g'`
    set -- $keyvalue_line
    value_part=$2
    if [ ! -z "$value_part" ] && [ $value_part -eq 0 ]
    then
        strResult="true"
        strReason="net.ipv4.conf.all.accept_redirects is set as 0 in $target"
    else
        strResult="false"
        strReason="net.ipv4.conf.all.accept_redirects is not 0 in $target"
    fi
else
    strResult="false"
    strReason="File $target does not exist."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
