#!/bin/sh

prefix=$1

for i in /etc
do
    mode=`ls -ld ${prefix}$i`
    set -- $mode
    mode=$1

    #other=${mode:7}
    #writebit=${other:1:1}

    # TODO: Instead of using :7 which is a bash feature, I use cut for safety.
    other=`echo $mode | cut -b 8-10 -`
    writebit=`echo $mode | cut -b 9 -`
    
    if [ "$writebit" = "-" ]
    then
        strReason="Permissions set properly on $i"
        strResult="true"
    else
        strReason="Permissions not set properly on $i"
        strResult="false"
    fi
done

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
