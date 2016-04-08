#!/bin/sh

prefix=$1
target="/var/log/tallylog"

if [ -e ${prefix}/lib/security/pam_tally2.so ] || [ -e ${prefix}/lib64/security/pam_tally2.so ]
then
        if [ -e ${prefix}${target} ]
        then
            strResult="true"
            strReason="File $target exists."
        else
            strResult="false"
            strReason="System uses pam_tally2.so, but the file $target does not exist."
        fi
else
        strResult="true"
        strReason="File $target does not exist. But, it is not required if pam_tally2.so is not used."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
