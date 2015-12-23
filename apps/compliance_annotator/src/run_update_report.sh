#!/bin/bash

second_counter=0
while true;
do
    /var/www/html/update_report.py $*
    echo "Sleeping. Time since start: $second_counter seconds."
    echo " "
    second_counter=`expr 1 + $second_counter`
    sleep 1
done
