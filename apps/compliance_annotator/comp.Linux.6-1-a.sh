#!/bin/sh

prefix=$1

# /etc/syslog.conf setting
if [ -f ${prefix}/etc/syslog.conf ]
then
    stanza1=`grep '^\*.info;mail.none;authpriv.none;cron.none[  ]*/var/log/messages' ${prefix}/etc/syslog.conf`
    stanza2=`grep '^authpriv.*[     ]*/var/log/secure' ${prefix}/etc/syslog.conf`

    if [ -z "$stanza1" ] || [ -z "$stanza2" ]
    then
        strReason="Login success or failure (Requirements for systems that use syslog) - Incorrect"
        strResult="false"
    else
        strReason="Login success or failure (Requirements for systems that use syslog)"
        strResult="true"
    fi
else
    strReason="Login success or failure (Requirements for systems that use syslog) - Missing /etc/syslog.conf"
    strResult="false"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","

