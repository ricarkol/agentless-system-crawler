#!/bin/sh

if [ $#  -ne 4 ]; then
        echo 1>&2 "Creates a writeable COW device for the specified disk, and mounts the COW device on the given mount point"
        echo 1>&2 "  "
        echo 1>&2 "Usage: $0 <device/partition> <COW space> <COW device name> <mnt point>"
        echo 1>&2 "  i.e.: $0 /dev/sdb1 /root/crawlDiskCow crawlDiskCow /mnt/crawlDisk/"
        echo 1>&2 "  "
        exit 1
fi

echo "Setting up COW device $3(-->$2) for $1:"
numSectors=`blockdev --getsz $1`; echo $numSectors
dd if=/dev/zero of=$2 bs=512 seek=$numSectors count=0
dd if=/dev/zero of=$2 bs=1 count=512 conv=notrunc
#loopDev=`losetup -vf $2 | grep "Loop device" | awk '{ print $4 }'`; echo $loopDev
# Update for FC17: losetup -v does not return loop dev anymore. Use below instead:
loopDev=`losetup --show -f $2`; echo $loopDev
dmsetup create -v $3 --table "0 $numSectors snapshot $1 $loopDev p 8"
echo "Mounting $3 on $4:"
mount -o ro /dev/mapper/$3 $4
