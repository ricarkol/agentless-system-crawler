#!/bin/sh

prefix=$1


if [ -e ${prefix}/etc/pam.d/rlogin -a -e ${prefix}/etc/pam.d/rsh -a -e ${prefix}/lib/security/pam_rhosts_auth.so ] 
then
    rez=`grep no_hosts_equiv ${prefix}/etc/pam.d/rsh`
    if [ -z "$rez" ]
    then
        strReason="etc/pam.d/rlogin, /etc/pam.d/rsh: no stanza"
        strResult="false"
    else
        strReason="etc/pam.d/rlogin, /etc/pam.d/rsh: no_hosts_equiv parameter is present."
        strResult="true"
    fi
else
    strReason="Since etc/pam.d/rlogin, /etc/pam.d/rsh do not exist, this rule does not apply."
    strResult="true"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","

