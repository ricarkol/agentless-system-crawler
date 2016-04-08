#!/bin/sh

prefix=$1
target="/var/log"

if [ -d ${prefix}${target} ]
then

    mode=`ls -ld ${prefix}${target}`
    set -- $mode
    mode=$1

    #other=${mode:7}
    #writebit=${other:1:1}

    # TODO: Instead of using :7 which is a bash feature, I use cut for safety.
    other=`echo $mode | cut -b 8-10 -`
    writebit=`echo $mode | cut -b 9 -`
    
    if [ "$writebit" = "-" ]
    then
        strReason="Permissions set properly on ${target}"
        strResult="true"
    else
        strReason="Permissions not set properly on ${target}"
        strResult="false"
    fi
else
    strReason="Directory ${target} missing."
    strResult="false"
fi


echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
