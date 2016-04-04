#!/bin/sh

prefix=$1
target="/var/log/wtmp"

if [ -e ${prefix}${target}  ]
then
    mode=`ls -ld ${prefix}${target}`
    set -- $mode
    mode=$1
    permbit1=`echo $mode | cut -b 6 -`
    permbit2=`echo $mode | cut -b 9 -`
    permbit=${permbit1}${permbit2}

    if [ "$permbit" = "--" ]
    then
        strReason="Permissions set properly on $target as $mode"
        strResult="true"
    else
        strReason="Permissions of $target is ${mode}. It should be rwxr-xr-x or more restrictive."
        strResult="false"
    fi
else
    strReason="File $file_naem does not exist. It must exist."
    strResult="false"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
