#!/bin/sh

prefix=$1
target="/etc/login.defs"

if [ -f ${prefix}${target} ]
then
    keyvalue_line=`grep ^UMASK ${prefix}${target}`
    set -- $keyvalue_line
    value_part=$2
    if [ ! -z "$value_part" ] && [ $value_part -eq 077 ]
    then
        strResult="true"
        strReason="UMASK is set as 077 in $target"
    else
        strResult="false"
        strReason="UMASK is not 077 in $target. Current value is $value_part."
    fi
else
    strResult="false"
    strReason="File $target does not exist."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
