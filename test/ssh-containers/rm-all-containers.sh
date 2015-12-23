
#!/bin/bash

. all_combinations

for i in "${arr[@]}"
do
	docker rm -f $i.instance > /dev/null
done
