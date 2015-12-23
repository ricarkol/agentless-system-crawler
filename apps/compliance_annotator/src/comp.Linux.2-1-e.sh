#!/bin/sh

prefix=$1

#
# Remember parameter of pam_unix.so
#
if [ -f ${prefix}/etc/pam.d/system-auth ]
then
    passwd=`grep '^password' ${prefix}/etc/pam.d/system-auth | grep 'remember\=7' `
    if [ -z "$passwd" ]
        then
            strReason="remember=7 parameter not set in /etc/pam.d/system-auth in password stanza"
            strResult="false"
        else
            strReason="remember=7 parameter set in /etc/pam.d/system-auth in password stanza"
            strResult="true"
    fi
else
    # Check the other four files for the stanza
    if [ -f ${prefix}/etc/pam.d/login ] && [ -f ${prefix}/etc/pam.d/passwd ]
    then
        passwd1=`grep '^password' ${prefix}/etc/pam.d/login | grep 'remember\=7' `
        passwd2=`grep '^password' ${prefix}/etc/pam.d/passwd | grep 'remember\=7' `
        if [ ! -z "$passwd1" ] && [ ! -z "$passwd2" ]
        then
            strReason="remember=7 parameter is set correctly in /etc/pam.d/login & /etc/pam.d/passwd"
            strResult="true"
        else
            strReason="remember=7 parameter not set in /etc/pam.d/login or /etc/pam.d/passwd"
            strResult="false"
        fi
    else
        strReason="/etc/pam.d/system-auth AND (/etc/pam.d/login & /etc/pam.d/passwd) does not exist"
        strResult="false"
    fi
fi

#shc_1line_output_description_html "Immediately expire new and manually reset passwords <br />Note: This is a process directive and cannot be health checked"
#shc_true_status_html
#complcount=`expr $complcount + 1`

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","

