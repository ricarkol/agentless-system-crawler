from yapsy.IPlugin import IPlugin


class IContainerCrawler(IPlugin):

    """
    Crawler plugin interface

    Subclasses of this class can be used to implement crawling functions
    for different systems.
    """
    def crawl(container_id):
        """
        Crawling function that should return a list of features for
        `container_id`. This function is called once for every container
        at every crawling interval.
        """
        raise NotImplementedError()
