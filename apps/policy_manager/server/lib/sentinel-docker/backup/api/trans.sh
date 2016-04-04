#!/bin/sh
ARRAY=(containers.rb container_groups.rb container_rules.rb rules.rb rule_groups.rb)
for f in ${ARRAY[@]}; do
  sed -i -e "s/system/container/g" $f
  sed -i -e "s/System/Container/g" $f
  sed -i -e "s/policy/rule/g" $f
  sed -i -e "s/Policy/Rule/g" $f
  sed -i -e "s/policies/rules/g" $f
  sed -i -e "s/Policies/Rules/g" $f
done

