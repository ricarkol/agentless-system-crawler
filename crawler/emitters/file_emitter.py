import gzip
import shutil

try:
    from emitters.base_emitter import BaseEmitter
except ImportError:
    from crawler.emitters.base_emitter import BaseEmitter

class FileEmitter(BaseEmitter):
    def emit(self, iostream, compress=False,
             metadata={}, snapshot_num=0):
        """

        :param iostream: a CStringIO stream used to buffer the formatted features.
        :param compress:
        :param metadata:
        :param snapshot_num:
        :return:
        """
        output_path = self.url[len('file://'):]
        short_name = metadata.get('emit_shortname', '')
        file_suffix = '{0}.{1}'.format(short_name, snapshot_num)
        output_path = '{0}.{1}'.format(output_path, file_suffix)
        output_path += '.gz' if compress else ''

        with open(output_path, 'w') as fd:
            if compress:
                gzip_file = gzip.GzipFile(fileobj=fd, mode='w')
                gzip_file.write(iostream.getvalue())
                gzip_file.close()
            else:
                iostream.seek(0)
                shutil.copyfileobj(iostream, fd)