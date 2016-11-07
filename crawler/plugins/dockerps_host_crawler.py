try:
    from crawler.icrawl_plugin import IHostCrawler
except ImportError:
    from icrawl_plugin import IHostCrawler

import logging

logger = logging.getLogger('crawlutils')


class DockerpsHostCrawler(IHostCrawler):

    def get_feature(self):
        return 'dockerps'

    def crawl(self, **kwargs):
        logger.debug('Crawling %s' % (self.get_feature()))

        return crawl_dockerps(mp)
