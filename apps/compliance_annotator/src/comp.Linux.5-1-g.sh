#!/bin/sh

prefix=$1
target="/etc/shadow"

if [ -e ${prefix}${target} ]
then
    mode=`ls -ld ${prefix}${target}`
    set -- $mode
    mode=$1
    permbit=`echo $mode | cut -b 4-10 -`
    
    if [ "$permbit" = "-------" ]
    then
        strReason="Permissions set properly on $target as $mode"
        strResult="true"
    else
        strReason="Permissions of $target is $permbit. It should be rw------- or more restrictive."
        strResult="false"
    fi
else
    strReason="file/directory does not exist"
    strResult="true"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
