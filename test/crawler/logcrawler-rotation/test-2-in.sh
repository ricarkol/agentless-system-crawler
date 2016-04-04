# test logging without links

rm /var/log/messages
rm /var/log/messages1
ln -s /var/log/messages.1 /var/log/messages

for i in `seq 1 10`
do
	echo $i >> /var/log/messages.1
done

mv /var/log/messages.1 /tmp/test.log.1

for i in `seq 11 20`
do
	echo $i >> /var/log/messages.1
done
