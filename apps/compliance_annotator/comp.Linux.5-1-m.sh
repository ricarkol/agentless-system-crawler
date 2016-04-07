#!/bin/sh

prefix=$1
target="/var/log/faillog"

if [ -e ${prefix}/lib/security/pam_tally2.so ] || [ -e ${prefix}/lib64/security/pam_tally2.so ]
then
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
                strReason="Permissions of $target is ${mode}. It should be rw------- or more restrictive."
                strResult="false"
            fi

        else
            strResult="false"
            strReason="System uses pam_tally2.so, but the file /var/log/faillog does not exist."
        fi
else
        strResult="true"
        strReason="File /var/log/faillog does not exist. But, it is not required if pam_tally2.so is not used."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
