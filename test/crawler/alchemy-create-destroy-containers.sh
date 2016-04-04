for i in `seq 52 100`
do
	echo $i
	TO_DELETE=`ice ps | grep "ibmnode" | awk '{print $2}' | tail -n 1`
	ice rm -f ${TO_DELETE}
	echo "sleeping 300 seconds..."
	sleep 300
	ice run --name kollerr-$i --memory 64 registry.ng.bluemix.net/ibmnode:latest
	echo "sleeping 300 seconds..."
	sleep 300
done
