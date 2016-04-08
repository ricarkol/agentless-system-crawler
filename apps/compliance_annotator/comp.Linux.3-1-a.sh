#!/bin/sh

prefix=$1

if [ -e ${prefix}/etc/motd ]
then
        strResult="true"
        strReason="/etc/motd exists."
else
        strResult="false"
        strReason="/etc/motd does not exist."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
