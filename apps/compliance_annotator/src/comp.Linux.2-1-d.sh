#!/bin/sh

prefix=$1

#strReason="(PASS_MIN_LEN) - /etc/login.defs does not exist."
#strResult="false"

if [ -f ${prefix}/etc/login.defs ]
then
        min_age=`grep ^PASS_MIN_DAYS ${prefix}/etc/login.defs`
        set -- $min_age
        min_age=$2
        if [ $min_age="1" ]
        then
            strReason="PASS_MIN_DAYS set at 1 in /etc/login.defs"
            strResult="true"
        else
            strReason="PASS_MIN_DAYS not set at 1 in /etc/login.defs"
            strResult="false"
        fi

        for i in `cat ${prefix}/etc/shadow`
        do
            pw=`echo $i | awk -F":" '{print $2}'`
        if [ "$pw" != "!!" ] && [ "$pw" != "*" ]
        then
            field4=`echo $i | awk -F":" '{print $4}'`
            if [ "$field4" = "1" ]
            then
                field4=1
            else
                field4=0
            fi

#            ud=`echo $i | awk -F":" '{print $1}'`
#            udstcheck=no
#            udstflg=`grep "^user" policy.in | grep "|${ud}|" | head -1 | awk -F"|" '{print $4}'`
#            if [ ! -z "$udstflg" ] && [ "$udstflg" = "false" ]
#            then
#                    udstcheck=yes
#            elif [ ! -z "$udstflg" ] && [ "$udstflg" = "none" ]
#            then
#                    udstcheck=yes
#            fi

#            if [ "$udstcheck" = "yes" ]
#            then
#                plcymsg="`grep "^user" policy.in  | grep "|${ud}|" | head -1 | awk -F"|" '{print $2}'`"
#                shc_1line_output_description_html "User(policy.in): `echo $ud | awk '{printf "%-15s",$0}'` $plcymsg - Field-4-/etc/shadow-Exception"
#                shc_true_status_html
#                complcount=`expr $complcount + 1`
#            elif [ $field4 -ne 1 ]
#            then
#                echo "User: `echo $i | awk -F":" '{printf "%-15s\n",$1}'` field 4 in /etc/shadow not set at 1" >> /tmp/q2_3.$$
#                cat /tmp/q2_3.$$ >> /tmp/Non-Compliant-List.$$
#                shc_nline_output_description_html /tmp/q2_3.$$
#                shc_non_true_status_html
#                noncomplcount=`expr $noncomplcount + 1`
#            fi
        fi
        done
else
    strReason="(PASS_MIN_DAYS) - /etc/login.defs does not exist."
    strResult="false"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
