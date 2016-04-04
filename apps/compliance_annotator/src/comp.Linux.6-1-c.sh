#!/bin/sh

# TODO: detect if it is a Debian system or not.

prefix=$1
target="/var/log/syslog"

if [ -e ${prefix}/var/log/messages ]
then
        strResult="true"
        strReason="This compliance rule does not apply since this is a non-Debian system."
else
    if [ -e ${prefix}${target} ]
    then
        strResult="true"
        strReason="Log file $target exists."
    else
        strResult="false"
        strReason="Log file $target does not exist."
    fi
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
