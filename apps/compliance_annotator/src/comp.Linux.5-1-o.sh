#!/bin/sh

prefix=$1

target1="/var/log/messages"
target2="/var/log/syslog"


if [ -e ${prefix}${target1} ] || [ -e ${prefix}${target2} ]
then

    if [ -e ${prefix}${target1} ]
    then
        target=$target1
    fi
    if [ -e ${prefix}${target2} ]
    then
        target=$target2
    fi

    mode=`ls -ld ${prefix}${target}`
    set -- $mode
    mode=$1
    permbit1=`echo $mode | cut -b 6 -`
    permbit2=`echo $mode | cut -b 9 -`
    permbit=${permbit1}${permbit2}
    
    if [ "$permbit" = "--" ]
    then
        strResult="true"
        strReason="Permissions of $target is set properly as $mode"
    else
        strResult="false"
        strReason="Permissions of $target is $mode. It should be rwxr-xr-x or more restrictive."
    fi

else
    strResult="false"
    strReason="Either $target1 or $target2 must exist."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","

