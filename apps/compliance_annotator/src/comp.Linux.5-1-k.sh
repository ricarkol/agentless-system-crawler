#!/bin/sh

prefix=$1
target="/var/tmp"

if [ -e ${prefix}${target} ]
then
    mode=`ls -ld ${prefix}${target}`
    set -- $mode
    mode=$1
    permbit=`echo $mode | cut -b 2-10 -`
    
    if [ "$permbit" = "rwxrwxrwt" ]
    then
        strReason="Permissions set properly on $target as $permbit."
        strResult="true"
    else
        strReason="Permissions of $target is $permbit. It should be rwxrwxrwt."
        strResult="false"
    fi
else
    strReason="file/directory does not exist"
    strResult="true"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
