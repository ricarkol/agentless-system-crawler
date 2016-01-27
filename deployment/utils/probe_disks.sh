#!/bin/bash


#
# (c) IBM Research 2015
# Author: Nilton Bila <nilton@us.ibm.com>
#
echo "probe_disks.sh"

outfile=/tmp/partitions.txt

echo "parted -l:" >$outfile
/sbin/parted -l >> $outfile

echo "/proc/partitions:" >>$outfile
cat /proc/partitions >>$outfile

echo "df -T" >>$outfile
df -T >>$outfile

