#!/bin/sh

prefix=$1
target="/var/log/wtmp"

if [ -e ${prefix}${target} ]
then
        strResult="true"
        strReason="File $target exists."
else
        strResult="false"
        strReason="File $target does not exist. It must exist."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
