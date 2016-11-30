import cStringIO
import gzip

try:
    from emitters.base_emitter import BaseEmitter
except ImportError:
    from crawler.emitters.base_emitter import BaseEmitter

class StdoutEmitter(BaseEmitter):
    def emit(self, iostream, compress=False,
             metadata={}, snapshot_num=0):
        """

        :param iostream: a CStringIO stream used to buffer the formatted features.
        :param compress:
        :param metadata:
        :param snapshot_num:
        :return:
        """
        if compress:
            tempio = cStringIO.StringIO()
            gzip_file = gzip.GzipFile(fileobj=tempio, mode='w')
            gzip_file.write(iostream.getvalue().strip())
            gzip_file.close()
            print tempio.getvalue()
        else:
            print "%s" % iostream.getvalue().strip()
