#!/bin/sh

prefix=$1

strReason="No ftpusers file exists."
strResult="false"

if [ -f "${prefix}/etc/ftpusers" ]
then
    rootaccess=`grep ^root ${prefix}/etc/ftpusers`
    if [ -z "$rootaccess" ]
    then
        strReason="FTP access for root is not disabled"
        strResult="false"
    else
        strReason="FTP access for root is disabled"
        strResult="true"
    fi
fi

if [ -f "${prefix}/etc/vsftpd.ftpusers" ]
then
    rootaccess=`grep ^root ${prefix}/etc/ftpusers`
    if [ -z "$rootaccess" ]
    then
        strReason="FTP access for root is not disabled"
        strResult="false"
    else
        strReason="FTP access for root is disabled"
        strResult="true"
    fi
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","

