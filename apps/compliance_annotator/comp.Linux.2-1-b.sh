#!/bin/sh

prefix=$1
target="/etc/login.defs"

if [ -f ${prefix}${target} ]
then
    max_days=`grep ^PASS_MAX_DAYS ${prefix}${target}`
    set -- $max_days
    max_days=$2
    if [ ! -z "$max_days" ] && [ $max_days -eq 90 ]
    then
        strResult="true"
        strReason="PASS_MAX_DAYS is currently set as 90 in ${target}."
    else

        if [ "$max_days"=="" ]
        then
            min_len="not specified in ${target}"
        fi

        strResult="false"
        strReason="PASS_MAX_DAYS not set to be 90 in /etc/login.defs. It is currently ${max_days}."
    fi

#    # Field 5 of /etc/shadow must be 90.
#    for i in `cat ${prefix}/etc/shadow`
#    do
#        # But, it is not required for userids without passwords.
#        pw=`echo $i | awk -F":" '{print $2}'`
#        if [ "$pw" != "!!" ] && [ "$pw" != "*" ]
#        then
#            # field5 is the password max day
#            field5=`echo $i | awk -F":" '{print $5}'`
#            if [ "$field5" == "" ]
#            then
#                field5=0
#            fi
#
#            # user id
#            ud=`echo $i | awk -F":" '{print $1}'`
#            xflg=`grep "^${ud}:" ${prefix}/etc/passwd | awk -F":" '{print $2}'`
#            nlginflg=`echo $i | awk -F":" '{print $2}'`
#
#            ud=`echo $i | awk -F":" '{print $1}'`
#            udstcheck=no
#            udstflg=`grep "^user" policy.in | grep "|${ud}|" | head -1 | awk -F"|" '{print $4}'`
#            if [ ! -z "$udstflg" ] && [ "$udstflg" = "false" ]
#            then
#                udstcheck=yes
#            elif [ ! -z "$udstflg" ] && [ "$udstflg" = "none" ]
#            then
#                udstcheck=yes
#            fi
#
#            if [ $field5 -ne 90 ]
#            then
#                if [ `echo $i | awk -F":" '{print $1}'` = "root" ]
#                then
#                    strReason="User: `echo $i | awk -F":" '{printf "%-15s\n",$1}'` PASS_MAX_DAYS field in /etc/shadow not set at 90."
#                    strResult="true"
#                elif [ "$udstcheck" = "yes" ]
#                then
#                    strReason="User: `echo $i | awk -F":" '{printf "%-15s\n",$1}'` excempt from this rule."
#                    strResult="true"
#                else
#                    if [ "$xflg" = "x" ] && [ "$nlginflg" = "nologin" ]
#                    then
#                        strReason="User: `echo $i | awk -F":" '{printf "%-15s\n",$1}'` PASS_MAX_DAYS field in /etc/shadow not set at 90 - nlogin in /etc/shadow"
#                        strResult="true"
#                    else
#                        strReason="User: `echo $i | awk -F":" '{printf "%-15s\n",$1}'` PASS_MAX_DAYS field in /etc/shadow not set at 90"
#                        strResult="false"
#                    fi
#                fi
#            fi
#        fi
#    done
else
    strResult="false"
    strReason="/etc/login.defs does not exist."
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
