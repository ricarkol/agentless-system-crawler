import psutil

try:
    from crawler.features import DiskFeature
except ImportError:
    from features import DiskFeature

def crawl_disk_partitions():
    for partition in psutil.disk_partitions(all=True):
        pdiskusage = psutil.disk_usage(partition.mountpoint)
        yield (partition.mountpoint, DiskFeature(
            partition.device,
            100.0 - pdiskusage.percent,
            partition.fstype,
            partition.mountpoint,
            partition.opts,
            pdiskusage.total,
        ), 'disk')