try:
    import crawler.dockerutils as dockerutils
    from crawler.icrawl_plugin import IContainerCrawler
    from crawler.namespace import run_as_another_namespace, ALL_NAMESPACES
except ImportError:
    import dockerutils
    from icrawl_plugin import IContainerCrawler
    from namespace import run_as_another_namespace, ALL_NAMESPACES

import logging

logger = logging.getLogger('crawlutils')


class DockerinspectContainerCrawler(IContainerCrawler):

    def get_feature(self):
        return 'dockerinspect'

    def crawl(self, container_id, avoid_setns=False, **kwargs):
        inspect = dockerutils.exec_dockerinspect(container_id)
        state = inspect['State']
        pid = str(state['Pid'])
        logger.debug(
            'Crawling %s for container %s' %
            (self.get_feature(), container_id))

        if avoid_setns:
            mp = dockerutils.get_docker_container_rootfs_path(container_id)
            return crawl_dockerinspect(mp)
        else:  # in all other cases, including wrong mode set
            return run_as_another_namespace(pid,
                                            ALL_NAMESPACES,
                                            crawl_dockerinspect)
