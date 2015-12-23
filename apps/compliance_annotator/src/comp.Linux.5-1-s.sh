#!/bin/sh

prefix=$1
target="/etc/snmpd.conf /etc/snmp/snmpd.conf /etc/snmpd/snmpd.conf"

file_exists="false"
for i in $target
do
    if [ -e ${prefix}$i ]
    then
        file_exists="true"
        file_name=$i
    fi
done

if [ $file_exists = "true" ]
then
    mode=`ls -ld ${prefix}${file_name}`
    set -- $mode
    mode=$1
    permbit1=`echo $mode | cut -b 1 -`
    permbit2=`echo $mode | cut -b 4 -`
    permbit3=`echo $mode | cut -b 6-10 -`
    permbit=${permbit1}${permbit2}${permbit3}

    if [ "$permbit" = "-------" ]
    then
        strReason="Permissions set properly on $file_name as $mode"
        strResult="true"
    else
        strReason="Permissions of $file_name is ${mode}. It should be 0640 or more restrictive."
        strResult="false"
    fi
else
    strReason="File $file_naem does not exist, but it is not required to exist."
    strResult="true"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
