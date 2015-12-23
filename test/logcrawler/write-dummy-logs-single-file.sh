
for i in `seq 1 10`
do
	for j in `seq 1 50000`
	do
		echo holaholaholaholaholaholaholaholaholaholaholaholaholaholaholaholaholaholaholahoholaholaholaholaholah >> /var/log/crawler_container_logs/d5c00fbb-90b6-4ace-b69a-0e4e7bd28083/0000/19459c21-e1bd-42f9-a5d3-8808ba250947/test.log
	done
	# write 100 * 50000 bytes (5.000.000) every second
	sleep 1
done
