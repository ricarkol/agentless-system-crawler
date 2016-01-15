PID=`awk '{print $1}' crawler.pid | head -n 1`
# kill the whole group
kill -9 -$PID
# just kill the parent
kill -9 $PID
