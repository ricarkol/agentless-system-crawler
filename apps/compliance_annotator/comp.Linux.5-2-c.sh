#!/bin/sh

prefix=$1

# /etc/pam.d/other
if [ -f ${prefix}/etc/pam.d/other ]
then
    stanza1=`grep '^auth[[:blank:]]*required' ${prefix}/etc/pam.d/other | grep 'pam_deny.so$'`
    stanza2=`grep '^account[[:blank:]]*required' ${prefix}/etc/pam.d/other | grep 'pam_deny.so$'`

    if [ -z "$stanza1" ] || [ -z "$stanza2" ]
    then
        strReason="/etc/pam.d/other does not enforce a default no access policy"
        strResult="false"
    else
        strReason="/etc/pam.d/other does enforce a default no access policy"
        strResult="true"
    fi
else
    strReason="/etc/pam.d/other does not exist"
    strResult="false"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","

