import logging

try:
    from base_crawler import BaseFrame
    from emitters.base_emitter import BaseEmitter
    from mtgraphite import MTGraphiteClient
except ImportError:
    from crawler.base_crawler import BaseFrame
    from crawler.emitters.base_emitter import BaseEmitter
    from crawler.mtgraphite import MTGraphiteClient

logger = logging.getLogger('crawlutils')


class MtGraphiteEmitter(BaseEmitter):
    def __init__(self, url, timeout=1, max_retries=5):
        BaseEmitter.__init__(self, timeout, max_retries)
        self.mtgraphite_client = MTGraphiteClient(self.url)

    def emit(self, iostream, compress=False,
             metadata={}, snapshot_num=0):
        """

        :param iostream: a CStringIO stream used to buffer the formatted features.
        :param compress:
        :param metadata:
        :param snapshot_num:
        :return:
        """
        iostream.seek(0)
        num = self.mtgraphite_client.send_messages(iostream.readlines())
        logger.debug('Pushed %d messages to mtgraphite queue' % num)