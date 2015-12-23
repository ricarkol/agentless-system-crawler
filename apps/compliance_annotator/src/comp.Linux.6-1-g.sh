#!/bin/sh

prefix=$1

target1="/var/log/secure"
target2="/var/log/auth.log"

if [ -e ${prefix}${target1} ] || [ -e ${prefix}${target2} ]
then
    strResult="true"
    strReason="File $target1 or $target2 exists."
else
    strResult="false"
    strReason="Neither $target1 nor $target2 exists."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
