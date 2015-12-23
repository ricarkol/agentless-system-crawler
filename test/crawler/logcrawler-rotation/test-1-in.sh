# test logging without links
for i in `seq 1 10`
do
	echo $i >> /var/log/messages
done

mv /var/log/messages /tmp/test.log.1

for i in `seq 11 20`
do
	echo $i >> /var/log/messages
done
