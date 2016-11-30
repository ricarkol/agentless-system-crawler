import time
import requests
import logging

try:
    from emitters.base_emitter import BaseEmitter
except ImportError:
    from crawler.emitters.base_emitter import BaseEmitter

logger = logging.getLogger('crawlutils')

max_emit_retries = 5


class HttpEmitter(BaseEmitter):

    def emit(self, iostream, compress=False,
             metadata={}, snapshot_num=0):
        """

        :param iostream: a CStringIO stream used to buffer the formatted features.
        :param compress:
        :param metadata:
        :param snapshot_num:
        :return: None
        """
        headers = {'content-type': 'application/csv'}
        if compress:
            raise NotImplementedError('http emitter does not support gzip.')
        for attempt in range(max_emit_retries):
            try:
                response = requests.post(self.url, headers=headers,
                                         params=metadata,
                                         data=iostream.getvalue())
            except requests.exceptions.ChunkedEncodingError as e:
                logger.exception(e)
                logger.error(
                    "POST to %s resulted in exception (attempt %d of %d), "
                    "will not re-try" % (self.url, attempt + 1, max_emit_retries))
                break
            except requests.exceptions.RequestException as e:
                logger.exception(e)
                logger.error(
                    "POST to %s resulted in exception (attempt %d of %d)" %
                    (self.url, attempt + 1, max_emit_retries))
                time.sleep(2.0 ** attempt * 0.1)
                continue
            if response.status_code != requests.codes.ok:
                logger.error("POST to %s resulted in status code %s: %s "
                             "(attempt %d of %d)" %
                             (self.url, str(response.status_code),
                              response.text, attempt + 1, max_emit_retries))
                time.sleep(2.0 ** attempt * 0.1)
            else:
                break
