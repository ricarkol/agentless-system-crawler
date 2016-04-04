#!/bin/sh

appendString() 
{
    local output
    
    local param1="${1}"
    local param2="${2}"
    
    if [ "$param1" = "" ]
    then
        echo "$param2"
    else
        echo "$param1, $param2"
    fi

}

prefix=$1

currentDate=$(date "+%s")
ncUsers=""
ok=1

for i in `grep "sh$" ${prefix}/etc/passwd | awk -F":" '{print $1}'`
do
    chage -l ${i} > /dev/null
    if [ $? -eq 0 ]
    then
        dateStr=$(chage -l ${i} | grep "Last password change" | awk -F": " '{print $2}')
        if [ "$dateStr" = "Never" ] 
        then 
            ok=0
            ncUsers=$( appendString "$ncUsers" "${i}($dateStr)" )
        else 
            passDate=$(date -d "$dateStr" "+%s")
            dif=$(($((currentDate - passDate)) / 86400))
            # Checking if password change date is more than 90 days ago
            if [ "$dif" -gt "90" ]
            then
                ok=0
                ncUsers=$( appendString "$ncUsers" "${i}($dateStr)" )
            fi
        fi
    else
        ok=0
        ncUsers=$( appendString "$ncUsers" "${i}(N/A)" )
    fi
done
    
if [ "$ok" -eq "1" ]
then
    strResult="true"
    strReason="Successfully verified that all user passwords have been changed."
else
    strResult="false"
    strReason="Found that following users have not changed initial default password: $ncUsers"
fi

echo "   \"compliant\":\""$strResult"\","
echo "   \"reason\":\""$strReason"\","
