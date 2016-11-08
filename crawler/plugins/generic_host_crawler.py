try:
    from crawler.icrawl_plugin import IHostCrawler
except ImportError:
    from icrawl_plugin import IHostCrawler

import logging

logger = logging.getLogger('crawlutils')


class __GENERIC_UPPERCASE__HostCrawler(IHostCrawler):

    def get_feature(self):
        return '__GENERIC__'

    def crawl(self, **kwargs):
        logger.debug('Crawling %s' % (self.get_feature()))

        return crawl___GENERIC__(mp)
