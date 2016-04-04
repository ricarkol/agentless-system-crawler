#!/bin/sh

prefix=$1
target="~root/.netrc"

if [ -e ${prefix}${target} ]
then
    mode=`ls -ld ${prefix}${target}`
    set -- $mode
    permbit=$1

    if [ "$permbit" = "-rw-------" ]
    then
        strReason="Read/write access of $target only by root."
        strResult="true"
    else
        strReason="Read/write access of $target must be only by root."
        strResult="false"
    fi
else
    strReason="File $target does not exist, but it is optional."
    strResult="true"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
