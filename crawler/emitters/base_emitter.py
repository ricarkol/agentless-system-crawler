class BaseEmitter:
    """
    Base emitter class from which emitters like FileEmitter, StdoutEmitter
    should inherit. The main idea is that all emitters get a url, and should
    implement an emit() function given an iostream (a buffer with the features
    to emit).
    """
    def __init__(self, url):
        self.url = url

    def emit(self, iostream, compress=False,
             metadata={}, snapshot_num=0):
        """

        :param iostream: a CStringIO stream used to buffer the formatted features.
        :param compress:
        :param metadata:
        :param snapshot_num:
        :return:
        """
        pass