#!/bin/sh

prefix=$1
target="/etc/profile.d/IBMsinit.csh"

if [ -e ${prefix}${target} ]
then
    mode=`ls -ld ${prefix}${target}`
    set -- $mode
    mode=$1
    permbit=`echo $mode | cut -b 5-10 -`
    
    if [ "$permbit" = "r-xr-x" ]
    then
        strReason="Permissions set properly on $target as $mode"
        strResult="true"
    else
        strReason="Permissions of $target for 'other' and 'group' is $permbit. It should be 'r-xr-x'."
        strResult="false"
    fi
else
    strReason="File $target does not exist."
    strResult="false"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
