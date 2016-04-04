#!/bin/sh

prefix=$1

strResult="false"
strReason="Either /var/log/secure or /var/log/auth.log must exist."

target1="/var/log/secure"
target2="/var/log/auth.log"

if [ -e ${prefix}${target1} ] || [ -e ${prefix}${target2} ]
then

    # Make a list of existing files because both file can exist.
    if [ -e ${prefix}${target1} ]
    then
        target_file_list=$target1
    fi
    if [ -e ${prefix}${target2} ]
    then
        target_file_list="$target_file_list $target2"
    fi

    # Initial results
    for f in $target_file_list
    do
        mode=`ls -ld ${prefix}${f}`
        set -- $mode
        mode=$1
        tmpstr="$tmpstr ${f}:${mode}"
    done
    strReason="Permissions set properly. $tmpstr"
    strResult="true"

    # If any of the file violates the permission, change the results.
    noncomp_found="false"
    for f in $target_file_list
    do
        mode=`ls -ld ${prefix}${f}`
        set -- $mode
        mode=$1
        permbit1=`echo $mode | cut -b 6 -`
        permbit2=`echo $mode | cut -b 8-10 -`
        permbit=${permbit1}${permbit2}
    
        if [ "$permbit" != "----" ]
        then
            noncomp_found="true"
            noncomp_reason="$noncomp_reason Permissions of $f is ${mode}. It should be rwxr-x--- or more restrictive."
        fi
    done

    if [ $noncomp_found = "true" ]
    then
        strReason=$noncomp_reason
        strResult="false"
    fi


else
    strResult="false"
    strReason="Neither $target1 nor $target2 exists."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
