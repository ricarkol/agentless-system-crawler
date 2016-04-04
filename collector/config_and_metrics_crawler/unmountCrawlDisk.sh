#!/bin/sh

if [ $#  -ne 4 ]; then
        echo 1>&2 "Unmounts the cow device from the given mount point."
        echo 1>&2 "Removes the underlying COW device, loop device and the configured cow space."
        echo 1>&2 "  "
        echo 1>&2 "Usage: $0 <loop device> <COW space> <COW device name> <mnt point>"
        echo 1>&2 "  i.e.: $0 /dev/loop0 /root/crawlDiskCow /dev/mapper/crawlDiskCow /mnt/crawlDisk/"
        echo 1>&2 "  "
        exit 1
fi

echo "Unmounting mount point $4"
umount $4
echo "Removing COW (dm) device $3"
dmsetup remove $3
echo "Removing loop dev $1"
losetup -d $1
echo "Deleting COW space $2"
rm -f $2

