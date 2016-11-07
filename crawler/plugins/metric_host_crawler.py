try:
    from crawler.icrawl_plugin import IHostCrawler
except ImportError:
    from icrawl_plugin import IHostCrawler

import logging

logger = logging.getLogger('crawlutils')


class MetricHostCrawler(IHostCrawler):

    def get_feature(self):
        return 'metric'

    def crawl(self, **kwargs):
        logger.debug('Crawling %s' % (self.get_feature()))

        return crawl_metric(mp)
