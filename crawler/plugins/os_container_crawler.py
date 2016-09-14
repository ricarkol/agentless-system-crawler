import os

try:
    from crawler.icrawl_plugin import IContainerCrawler
    from crawler.features import OSFeature
except ImportError:
    from icrawl_plugin import IContainerCrawler
    from features import OSFeature

class OSContainerCrawler(IContainerCrawler):

    def crawl(self, container_id):
        print container_id
        return [OSFeature(1,2,3,4,5,6,7)]
