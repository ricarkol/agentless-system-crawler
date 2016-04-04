
#!/bin/bash

. all_combinations

for i in "${arr[@]}"
do
	docker rmi -f $i > /dev/null
done
