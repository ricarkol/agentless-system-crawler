try:
    import crawler.dockerutils as dockerutils
    from crawler.icrawl_plugin import IContainerCrawler
    from crawler.namespace import run_as_another_namespace, ALL_NAMESPACES
    from crawler.features import MetricFeature
    from crawler.plugins.metric_crawler import crawl_metrics
except ImportError:
    import dockerutils
    from icrawl_plugin import IContainerCrawler
    from namespace import run_as_another_namespace, ALL_NAMESPACES
    from features import MetricFeature
    from plugins.metric_crawler import crawl_metrics

import logging

logger = logging.getLogger('crawlutils')


class MetricContainerCrawler(IContainerCrawler):

    def get_feature(self):
        return 'metric'

    def crawl(self, container_id, avoid_setns=False, **kwargs):
        inspect = dockerutils.exec_dockerinspect(container_id)
        state = inspect['State']
        pid = str(state['Pid'])
        logger.debug('Crawling %s for container %s' % (self.get_feature(), container_id))

        if avoid_setns:
            raise NotImplementedError('avoidsetns mode not implemented')
        else:  # in all other cases, including wrong mode set
            return run_as_another_namespace(pid,
                                            ALL_NAMESPACES,
                                            crawl_metrics)
