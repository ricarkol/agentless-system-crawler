#!/bin/sh

prefix=$1
target="/etc/pam.d/common-password"

if [ -e ${prefix}${target} ]
then
    tmpstr=`grep ^password ${prefix}/etc/pam.d/common-password | grep -o 'minlen=[^ ,]\+' | sed 's/=/ /g'`
    set -- $tmpstr
    min_len=$2
    if [ ! -z "$min_len" ] && [ "$min_len" -ge 8 ]
    then
        strReason="Minimum password length is ${min_len}, which is >= 8."
        strResult="true"
    else
        if [ "$min_len"=="" ]
        then
            min_len="not specified in ${target}. Default is 6"
        fi

        strReason="Minimum password length is ${min_len}. It is recommended to be at least 8."
        strResult="false"
    fi
        
#    pam_crack=0;
#    if [ -f ${prefix}/etc/pam.d/system-auth ]
#    then
#            stanza=`grep '^password[ ]*required[ ]*pam_craklib.so[ ]' ${prefix}/etc/pam.d/system-auth`
#    fi
    
else
    strReason="(PASS_MIN_LEN) - /etc/pam.d/common-password does not exist."
    strResult="false"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
