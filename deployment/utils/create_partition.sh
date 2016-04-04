#!/bin/bash


#
# Vulnerability Advisor partition creation
# (c) IBM Research 2015
#

if [ $# -lt 6 ] || [ $# -gt 8 ] 
    then
    echo "Usage $0 <device> <start> <end> <partition-number> <fstype> <mountpoint> <overwrite>"
    exit 1
fi

device=$1
partition_start=$2
partition_end=$3
partition_number=$4
fstype=$5
mountpoint=$6
overwrite=$7

PARTED="/sbin/parted -s --"
FDISK="/sbin/fdisk"

out=$($FDISK -l $device)
err=$($FDISK -l $device 2>&1 >/dev/null)
if [ -z "$out" ]
   then
   echo "Device $device does not exist"
   exit 1
fi

apt-get -y install btrfs-tools

set -x
echo "Setting device label on $device"

if [ -z "$err" ] 
   then
   echo "Device $device already has a partition table or label"
else
   $PARTED $device mklabel msdos
fi

err=$($FDISK -l $device$partition_number 2>&1 >/dev/null)
if [[ -n "$err" && "$overwrite" != "true" ]] 
   then
   echo "Partition $device$partition_number exists already "
   exit 0
fi

umount $device$partition_number

if [ "$overwrite" = "true" ]
then
   echo "Removing partition $device$partition_number"
   $PARTED $device rm $partition_number
fi

echo "Creating partition $partition_number on $device "
$PARTED $device mkpart primary $partition_start $partition_end

if [ $? -ne 0 ]
    then 
    echo "Failed to create partition $device$partition_number"
    exit 1
fi

echo "Creating file system on $device$partition_number"

if [ "$overwrite" = "true" ]
then
    mkfs.${fstype} -f $device$partition_number
else
    mkfs.${fstype} $device$partition_number
fi

if [ $? -ne 0 ]
    then 
    echo "Failed to create file system on $device$partition_number"
    exit 1
fi

echo "Creating mountpoint in $mountpoint"
mkdir -p $mountpoint
if [ $? -ne 0 ]
    then 
    echo "Failed to create mountpoint $mountpoint"
    exit 1
fi

#grep to check if $device not already in fstab
echo "Adding filesystem at $device${partition_number} to /etc/fstab"
if [ "$fstype" = "btrfs" ]
    then
    fsckfs=0
else
    fsckfs=2
fi

if [ -z "$err" ]
then
    echo "$device${partition_number}	$mountpoint	$fstype	auto,noatime	0	$fsckfs" >>/etc/fstab 
fi

#mount "$device${partition_number}" $mountpoint
echo "mounting new partition"
mount -a
