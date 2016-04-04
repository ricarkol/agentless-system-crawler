#!/bin/bash

. all_combinations

for i in "${arr[@]}"
do
	(cd images/$i; docker build -t $i .)
done
