try:
    from crawler.icrawl_plugin import IVMCrawler
    # XXX: make crawler agnostic of this
    from crawler.features import __GENERIC_UPPERCASE__Feature
except ImportError:
    from icrawl_plugin import IVMCrawler
    # XXX: make crawler agnostic of this
    from features import __GENERIC_UPPERCASE__Feature
import logging

# External dependencies that must be pip install'ed separately

import psutil

try:
    import psvmi
except ImportError:
    psvmi = None

logger = logging.getLogger('crawlutils')


class __GENERIC___vm_crawler(IVMCrawler):

    def get_feature(self):
        return '__GENERIC__'

    def crawl(self, vm_desc, **kwargs):
        if psvmi is None:
            raise NotImplementedError()
        else:
            (domain_name, kernel_version, distro, arch) = vm_desc
            # XXX: this has to be read from some cache instead of
            # instead of once per plugin/feature
            vm_context = psvmi.context_init(
                domain_name, domain_name, kernel_version, distro, arch)

            created_since = -1
            for p in psvmi.__GENERIC___iter(vm_context):
                create_time = (
                    p.create_time() if hasattr(
                        p.create_time,
                        '__call__') else p.create_time)
                if create_time <= created_since:
                    continue
                yield self._crawl_single___GENERIC__(p)
