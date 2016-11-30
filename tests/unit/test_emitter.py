from capturing import Capturing
import mock
import unittest
import requests.exceptions
import tempfile
import os
import gzip
import cStringIO

import crawler.crawler_exceptions
from crawler.emitters_manager import EmittersManager
from crawler.base_crawler import BaseFrame
from crawler.emitters.http_emitter import HttpEmitter
from crawler.emitters.kafka_emitter import KafkaEmitter, kafka_send
from crawler.emitters.mtgraphite_emitter import MtGraphiteEmitter

def mocked_requests_post(*args, **kwargs):
    class MockResponse:

        def __init__(self, status_code):
            self.status_code = status_code
            self.text = 'blablableble'

        def json(self):
            return self.json_data
    if args[0] == 'http://1.1.1.1/good':
        return MockResponse(status_code=200)
    elif args[0] == 'http://1.1.1.1/bad':
        return MockResponse(status_code=500)
    elif args[0] == 'http://1.1.1.1/exception':
        raise requests.exceptions.RequestException('bla')
    elif args[0] == 'http://1.1.1.1/encoding_error':
        raise requests.exceptions.ChunkedEncodingError('bla')

class MockedKafkaClient1:

    def __init__(self, kurl):
        print 'kafka_python init'
        pass

    def ensure_topic_exists(self, topic):
        return True


class RandomKafkaException(Exception):
    pass


def raise_value_error(*args, **kwargs):
    raise ValueError()

class MockProducer:

    def __init__(self, good=True, timeout=False):
        self.good = good
        self.timeout = timeout

    def produce(self, msgs=[]):
        print 'produce'
        if self.good:
            print msgs
        else:
            raise RandomKafkaException('random kafka exception')
        if self.timeout:
            while True:
                a = 1
                assert a


class MockTopic:

    def __init__(self, good=True, timeout=False):
        self.good = good
        self.timeout = timeout

    def get_producer(self):
        print 'get producer'
        return MockProducer(good=self.good, timeout=self.timeout)


class MockedKafkaClient2:

    def __init__(self, hosts=[]):
        print 'pykafka init'
        self.topics = {'topic1': MockTopic(good=True),
                       'badtopic': MockTopic(good=False),
                       'timeouttopic': MockTopic(timeout=True)}


class MockedMTGraphiteClient:

    def __init__(self, url):
        pass

    def send_messages(self, messages):
        return 1


# TODO (ricarkol): It would be nice to avoid all side effects and mock all
# temp files being created.


class EmitterTests(unittest.TestCase):
    image_name = 'alpine:latest'

    def setUp(self):
        pass

    def tearDown(self):
        pass

    def _test_emitter_csv_simple_stdout(self, compress=False):
        emitter = EmittersManager(urls=['stdout://'],
                                  compress=compress)
        frame = BaseFrame(feature_types=['os'])
        frame.add_features([("dummy_feature",
                     {'test': 'bla',
                      'test2': 12345,
                      'test3': 12345.0,
                      'test4': 12345.00000},
                     'dummy_feature')])
        emitter.emit(frame, 0)

    def test_emitter_csv_simple_stdout(self):
        with Capturing() as _output:
            self._test_emitter_csv_simple_stdout()
        output = "%s" % _output
        print _output
        assert len(_output) == 2
        assert "dummy_feature" in output
        assert "metadata" in output

    def test_emitter_csv_compressed_stdout(self):
        with Capturing() as _output:
            self._test_emitter_csv_simple_stdout(compress=True)
        output = "%s" % _output
        assert 'metadata' not in output
        assert len(output) > 0

    def test_emitter_csv_simple_file(self):
        emitter = EmittersManager(urls=['file:///tmp/test_emitter'],
                                  compress=False)
        frame = BaseFrame(feature_types=['os'])
        frame.add_features([("dummy_feature",
                     {'test': 'bla',
                      'test2': 12345,
                      'test3': 12345.0,
                      'test4': 12345.00000},
                     'dummy_feature')])
        emitter.emit(frame, 0)
        with open('/tmp/test_emitter.0') as f:
            _output = f.readlines()
            output = "%s" % _output
            print output
            assert len(_output) == 2
            assert "dummy_feature" in output
            assert "metadata" in output

    def test_emitter_all_features_compressed_csv(self):
        emitter = EmittersManager(urls=['file:///tmp/test_emitter'],
                                  compress=True)
        frame = BaseFrame(feature_types=[])
        frame.add_feature("memory", {'test3': 12345}, 'memory')
        frame.add_feature("memory_0", {'test3': 12345}, 'memory')
        frame.add_feature("load", {'load': 12345}, 'load')
        frame.add_feature("cpu", {'test3': 12345}, 'cpu')
        frame.add_feature("cpu_0", {'test3': 12345}, 'cpu')
        frame.add_feature("eth0", {'if_tx': 12345}, 'interface')
        frame.add_feature("eth0", {'if_rx': 12345}, 'interface')
        frame.add_feature("bla/bla", {'ble/ble': 12345}, 'disk')
        emitter.emit(frame, 0)
        with gzip.open('/tmp/test_emitter.0.gz') as f:
            _output = f.readlines()
            output = "%s" % _output
            print output
            assert len(_output) == 9
            assert "metadata" in output

    def test_emitter_all_features_csv(self):
        emitter = EmittersManager(urls=['file:///tmp/test_emitter'])
        frame = BaseFrame(feature_types=[])
        frame.add_feature("memory", {'test3': 12345}, 'memory')
        frame.add_feature("memory_0", {'test3': 12345}, 'memory')
        frame.add_feature("load", {'load': 12345}, 'load')
        frame.add_feature("cpu", {'test3': 12345}, 'cpu')
        frame.add_feature("cpu_0", {'test3': 12345}, 'cpu')
        frame.add_feature("eth0", {'if_tx': 12345}, 'interface')
        frame.add_feature("eth0", {'if_rx': 12345}, 'interface')
        frame.add_feature("bla/bla", {'ble/ble': 12345}, 'disk')
        emitter.emit(frame, 0)
        with open('/tmp/test_emitter.0') as f:
            _output = f.readlines()
            output = "%s" % _output
            print output
            assert len(_output) == 9
            assert "metadata" in output

    def test_emitter_all_features_graphite(self):
        emitter = EmittersManager(urls=['file:///tmp/test_emitter'],
                                  format='graphite')
        frame = BaseFrame(feature_types=[])
        frame.add_feature("memory", {'test3': 12345}, 'memory')
        frame.add_feature("memory_0", {'test3': 12345}, 'memory')
        frame.add_feature("load", {'load': 12345}, 'load')
        frame.add_feature("cpu", {'test3': 12345}, 'cpu')
        frame.add_feature("cpu_0", {'test3': 12345}, 'cpu')
        frame.add_feature("eth0", {'if_tx': 12345}, 'interface')
        frame.add_feature("eth0", {'if_rx': 12345}, 'interface')
        frame.add_feature("bla/bla", {'ble/ble': 12345}, 'disk')
        emitter.emit(frame, 0)
        with open('/tmp/test_emitter.0') as f:
            _output = f.readlines()
            output = "%s" % _output
            print output
            assert 'memory-0.test3 12345' in output
            assert len(_output) == 8

    def _test_emitter_graphite_simple_stdout(self):
        emitter = EmittersManager(urls=['stdout://'],
                                  format='graphite')
        frame = BaseFrame(feature_types=[])
        frame.metadata['namespace'] = 'namespace777'
        frame.add_features([("dummy_feature",
                     {'test': 'bla',
                      'test2': 12345,
                      'test3': 12345.0,
                      'test4': 12345.00000},
                     'dummy_feature')])
        emitter.emit(frame, 0)

    def test_emitter_graphite_simple_stdout(self):
        with Capturing() as _output:
            self._test_emitter_graphite_simple_stdout()
        output = "%s" % _output
        # should look like this:
        # ['namespace777.dummy-feature.test3 3.000000 1449870719',
        #  'namespace777.dummy-feature.test2 2.000000 1449870719',
        #  'namespace777.dummy-feature.test4 4.000000 1449870719']
        assert len(_output) == 3
        assert "dummy_feature" not in output  # can't have '_'
        assert "dummy-feature" in output  # can't have '_'
        assert "metadata" not in output
        assert 'namespace777.dummy-feature.test2' in output
        assert 'namespace777.dummy-feature.test3' in output
        assert 'namespace777.dummy-feature.test4' in output
        # three fields in graphite format
        assert len(_output[0].split(' ')) == 3
        # three fields in graphite format
        assert len(_output[1].split(' ')) == 3
        # three fields in graphite format
        assert len(_output[2].split(' ')) == 3
        assert float(_output[0].split(' ')[1]) == 12345.0
        assert float(_output[1].split(' ')[1]) == 12345.0
        assert float(_output[2].split(' ')[1]) == 12345.0

    def test_emitter_unsupported_format(self):
        metadata = {}
        metadata['namespace'] = 'namespace777'
        with self.assertRaises(
                crawler.crawler_exceptions.EmitterUnsupportedFormat):
            _ = EmittersManager(urls=['file:///tmp/test_emitter'],
                                format='unsupported')

    @mock.patch('crawler.emitters_manager.FileEmitter.emit',
                side_effect=raise_value_error)
    def test_emitter_failed_emit(self, *args):
        with self.assertRaises(ValueError):
            emitter = EmittersManager(urls=['file:///tmp/test_emitter'],
                                      format='csv')
            frame = BaseFrame(feature_types=[])
            frame.metadata['namespace'] = 'namespace777'
            frame.add_feature("memory", {'test3': 12345}, 'memory')
            emitter.emit(frame)

    def test_emitter_unsuported_protocol(self):
        with self.assertRaises(
                crawler.crawler_exceptions.EmitterUnsupportedProtocol):
            _ = EmittersManager(urls=['error:///tmp/test_emitter'],
                                format='graphite')

    def test_emitter_graphite_simple_file(self):
        emitter = EmittersManager(urls=['file:///tmp/test_emitter'],
                                  format='graphite')
        frame = BaseFrame(feature_types=[])
        frame.metadata['namespace'] = 'namespace777'
        frame.add_features([("dummy_feature",
                     {'test': 'bla',
                      'test2': 12345,
                      'test3': 12345.0,
                      'test4': 12345.00000},
                     'dummy_feature')])
        emitter.emit(frame)
        with open('/tmp/test_emitter.0') as f:
            _output = f.readlines()
            output = "%s" % _output
            # should look like this:
            # ['namespace777.dummy-feature.test3 3.000000 1449870719',
            #  'namespace777.dummy-feature.test2 2.000000 1449870719',
            #  'namespace777.dummy-feature.test4 4.000000 1449870719']
            assert len(_output) == 3
            assert "dummy_feature" not in output  # can't have '_'
            assert "dummy-feature" in output  # can't have '_'
            assert "metadata" not in output
            assert 'namespace777.dummy-feature.test2' in output
            assert 'namespace777.dummy-feature.test3' in output
            assert 'namespace777.dummy-feature.test4' in output
            # three fields in graphite format
            assert len(_output[0].split(' ')) == 3
            # three fields in graphite format
            assert len(_output[1].split(' ')) == 3
            # three fields in graphite format
            assert len(_output[2].split(' ')) == 3
            assert float(_output[0].split(' ')[1]) == 12345.0
            assert float(_output[1].split(' ')[1]) == 12345.0
            assert float(_output[2].split(' ')[1]) == 12345.0

    def test_emitter_json_simple_file(self):
        emitter = EmittersManager(urls=['file:///tmp/test_emitter'],
                                  format='json')
        frame = BaseFrame(feature_types=[])
        frame.metadata['namespace'] = 'namespace777'
        frame.add_features([("dummy_feature",
                     {'test': 'bla',
                      'test2': 12345,
                      'test3': 12345.0,
                      'test4': 12345.00000},
                     'dummy_feature')])
        emitter.emit(frame)
        with open('/tmp/test_emitter.0') as f:
            _output = f.readlines()
            output = "%s" % _output
            print output
            assert len(_output) == 2
            assert "metadata" not in output
            assert ('{"test3": 12345.0, "test2": 12345, "test4": 12345.0, '
                    '"namespace": "namespace777", "test": "bla", "feature_type": '
                    '"dummy_feature"}') in output

    def test_emitter_graphite_simple_compressed_file(self):
        emitter = EmittersManager(urls=['file:///tmp/test_emitter'],
                                  format='graphite',
                                  compress=True)
        frame = BaseFrame(feature_types=[])
        frame.metadata['namespace'] = 'namespace777'
        frame.add_features([("dummy_feature",
                     {'test': 'bla',
                      'test2': 12345,
                      'test3': 12345.0,
                      'test4': 12345.00000},
                     'dummy_feature')])
        emitter.emit(frame)
        with gzip.open('/tmp/test_emitter.0.gz') as f:
            _output = f.readlines()
            output = "%s" % _output
            # should look like this:
            # ['namespace777.dummy-feature.test3 3.000000 1449870719',
            #  'namespace777.dummy-feature.test2 2.000000 1449870719',
            #  'namespace777.dummy-feature.test4 4.000000 1449870719']
            assert len(_output) == 3
            assert "dummy_feature" not in output  # can't have '_'
            assert "dummy-feature" in output  # can't have '_'
            assert "metadata" not in output
            assert 'namespace777.dummy-feature.test2' in output
            assert 'namespace777.dummy-feature.test3' in output
            assert 'namespace777.dummy-feature.test4' in output
            # three fields in graphite format
            assert len(_output[0].split(' ')) == 3
            # three fields in graphite format
            assert len(_output[1].split(' ')) == 3
            # three fields in graphite format
            assert len(_output[2].split(' ')) == 3
            assert float(_output[0].split(' ')[1]) == 12345.0
            assert float(_output[1].split(' ')[1]) == 12345.0
            assert float(_output[2].split(' ')[1]) == 12345.0

    @mock.patch('crawler.emitters.http_emitter.requests.post',
                side_effect=mocked_requests_post)
    @mock.patch('crawler.emitters.http_emitter.time.sleep')
    def test_emitter_http(self, mock_sleep, mock_post):
        emitter = HttpEmitter(url='http://1.1.1.1/good')
        iostream = cStringIO.StringIO()
        iostream.write('namespace777.dummy-feature.test2 12345 14804\r\n')
        iostream.write('namespace777.dummy-feature.test2 12345 14805\r\n')
        emitter.emit(iostream)
        self.assertEqual(mock_post.call_count, 1)

    @mock.patch('crawler.emitters.http_emitter.requests.post',
                side_effect=mocked_requests_post)
    @mock.patch('crawler.emitters.http_emitter.time.sleep')
    def test_emitter_http_server_error(self, mock_sleep, mock_post):
        emitter = HttpEmitter(url='http://1.1.1.1/bad')
        iostream = cStringIO.StringIO()
        iostream.write('namespace777.dummy-feature.test2 12345 14804\r\n')
        iostream.write('namespace777.dummy-feature.test2 12345 14805\r\n')
        emitter.emit(iostream)
        self.assertEqual(mock_post.call_count, 5)

    @mock.patch('crawler.emitters.http_emitter.requests.post',
                side_effect=mocked_requests_post)
    @mock.patch('crawler.emitters.http_emitter.time.sleep')
    def test_emitter_http_request_exception(self, mock_sleep, mock_post):
        emitter = HttpEmitter(url='http://1.1.1.1/exception')
        iostream = cStringIO.StringIO()
        iostream.write('namespace777.dummy-feature.test2 12345 14804\r\n')
        iostream.write('namespace777.dummy-feature.test2 12345 14805\r\n')
        emitter.emit(iostream)
        self.assertEqual(mock_post.call_count, 5)

    @mock.patch('crawler.emitters.http_emitter.requests.post',
                side_effect=mocked_requests_post)
    def test_emitter_http_encoding_error(self, mock_post):
        emitter = HttpEmitter(url='http://1.1.1.1/encoding_error')
        iostream = cStringIO.StringIO()
        iostream.write('namespace777.dummy-feature.test2 12345 14804\r\n')
        iostream.write('namespace777.dummy-feature.test2 12345 14805\r\n')
        emitter.emit(iostream)
        # there are no retries for encoding errors
        self.assertEqual(mock_post.call_count, 1)


    @mock.patch('crawler.emitters.kafka_emitter.pykafka.KafkaClient',
                side_effect=MockedKafkaClient2, autospec=True)
    @mock.patch('crawler.emitters.kafka_emitter.kafka_python.KafkaClient',
                side_effect=MockedKafkaClient1, autospec=True)
    @mock.patch('crawler.emitters.kafka_emitter.time.sleep')
    def test_emitter_csv_kafka_invalid_url(
            self, mockedSleep, MockKafkaClient1, MockKafkaClient2):
        with self.assertRaises(crawler.crawler_exceptions.EmitterBadURL):
            emitter = KafkaEmitter(url='kafka://abc')
            iostream = cStringIO.StringIO()
            iostream.write('namespace777.dummy-feature.test2 12345 14804\r\n')
            iostream.write('namespace777.dummy-feature.test2 12345 14805\r\n')
            emitter.emit(iostream)

    @mock.patch('crawler.emitters.kafka_emitter.pykafka.KafkaClient',
                side_effect=MockedKafkaClient2, autospec=True)
    @mock.patch('crawler.emitters.kafka_emitter.kafka_python.KafkaClient',
                side_effect=MockedKafkaClient1)
    @mock.patch('crawler.emitters.kafka_emitter.time.sleep')
    def test_emitter_kafka(
            self, mock_sleep, MockKafkaClient1, MockKafkaClient2, *args):
        emitter = KafkaEmitter(url='kafka://1.1.1.1:123/topic1')
        iostream = cStringIO.StringIO()
        iostream.write('namespace777.dummy-feature.test2 12345 14804\r\n')
        iostream.write('namespace777.dummy-feature.test2 12345 14805\r\n')
        emitter.emit(iostream)
        # there are no retries for encoding errors
        # XXX: MockKafkaClient1.call_count won't have the desifed effect and
        # will be 0 because it is called from another process. So, let's just
        # call the function and make sure no exception is thrown.

    @mock.patch('crawler.emitters.kafka_emitter.pykafka.KafkaClient',
                side_effect=MockedKafkaClient2, autospec=True)
    @mock.patch('crawler.emitters.kafka_emitter.kafka_python.KafkaClient',
                side_effect=MockedKafkaClient1)
    @mock.patch('crawler.emitters.kafka_emitter.time.sleep')
    def test_emitter_kafka_failed_emit(self, mock_sleep, MockC1, MockC2):
        emitter = KafkaEmitter(url='kafka://1.1.1.1:123/badtopic')
        iostream = cStringIO.StringIO()
        iostream.write('namespace777.dummy-feature.test2 12345 14804\r\n')
        iostream.write('namespace777.dummy-feature.test2 12345 14805\r\n')
        with self.assertRaises(RandomKafkaException):
            emitter.emit(iostream)

    @mock.patch('crawler.emitters.kafka_emitter.pykafka.KafkaClient',
                side_effect=MockedKafkaClient2, autospec=True)
    @mock.patch('crawler.emitters.kafka_emitter.kafka_python.KafkaClient',
                side_effect=MockedKafkaClient1)
    @mock.patch('crawler.emitters.kafka_emitter.time.sleep')
    def test_emitter_csv_kafka_failed_emit_no_retries(self, MockSleep, MockC1, MockC2):
        emitter = KafkaEmitter(url='kafka://1.1.1.1:123/badtopic',
                               max_retries=0)
        iostream = cStringIO.StringIO()
        iostream.write('namespace777.dummy-feature.test2 12345 14804\r\n')
        iostream.write('namespace777.dummy-feature.test2 12345 14805\r\n')
        with self.assertRaises(RandomKafkaException):
            emitter.emit(iostream)
            assert MockSleep.call_count == 0

    @mock.patch('crawler.emitters.kafka_emitter.pykafka.KafkaClient',
                side_effect=MockedKafkaClient2, autospec=True)
    @mock.patch('crawler.emitters.kafka_emitter.kafka_python.KafkaClient',
                side_effect=MockedKafkaClient1)
    @mock.patch('crawler.emitters.kafka_emitter.time.sleep')
    def test_emitter_csv_kafka_emit_timeout(self, mock_sleep, MockC1, MockC2):
        emitter = KafkaEmitter(url='kafka://1.1.1.1:123/timeouttopic',
                               max_retries=0)
        iostream = cStringIO.StringIO()
        iostream.write('namespace777.dummy-feature.test2 12345 14804\r\n')
        iostream.write('namespace777.dummy-feature.test2 12345 14805\r\n')
        with self.assertRaises(crawler.crawler_exceptions.EmitterEmitTimeout):
            emitter.emit(iostream)

    @mock.patch('crawler.emitters.kafka_emitter.multiprocessing.Process',
                side_effect=raise_value_error)
    def test_emitter_csv_kafka_failed_new_process(self, mock_process):
        emitter = KafkaEmitter(url='kafka://1.1.1.1:123/topic',
                               max_retries=0)
        iostream = cStringIO.StringIO()
        iostream.write('namespace777.dummy-feature.test2 12345 14804\r\n')
        iostream.write('namespace777.dummy-feature.test2 12345 14805\r\n')
        with self.assertRaises(ValueError):
            emitter.emit(iostream)

    @mock.patch('crawler.emitters.kafka_emitter.pykafka.KafkaClient',
                side_effect=MockedKafkaClient2, autospec=True)
    @mock.patch('crawler.emitters.kafka_emitter.kafka_python.KafkaClient',
                side_effect=MockedKafkaClient1, autospec=True)
    def test_emitter_kafka_send(self, MockC1, MockC2):
        (temp_fd, path) = tempfile.mkstemp(prefix='emit.')
        os.close(temp_fd)  # close temporary file descriptor
        emitfile = open(path, 'wb')
        tmp_message = 'a.b.c 1 1\r\n'
        emitfile.write(tmp_message)
        emitfile.write(tmp_message)
        emitfile.close()

        try:
            kafka_send('1.1.1.1', path, 'csv', 'topic1')
            kafka_send('1.1.1.1', path, 'graphite', 'topic1')
            with self.assertRaises(RandomKafkaException):
                kafka_send('1.1.1.1', path, 'csv', 'badtopic')
            with self.assertRaises(RandomKafkaException):
                kafka_send('1.1.1.1', path, 'graphite', 'badtopic')
            with self.assertRaises(
                    crawler.crawler_exceptions.EmitterUnsupportedFormat):
                kafka_send('1.1.1.1', path, 'xxx', 'badtopic')
        finally:
            os.remove(path)
        self.assertEqual(MockC1.call_count, 5)
        self.assertEqual(MockC1.call_count, 5)

    @mock.patch('crawler.emitters.mtgraphite_emitter.MTGraphiteClient',
                side_effect=MockedMTGraphiteClient, autospec=True)
    def test_emitter_mtgraphite(self, MockMTGraphiteClient):
        emitter = MtGraphiteEmitter(url='mtgraphite://1.1.1.1:123/topic1',
                                    max_retries=0)
        iostream = cStringIO.StringIO()
        iostream.write('namespace777.dummy-feature.test2 12345 14804\r\n')
        iostream.write('namespace777.dummy-feature.test2 12345 14805\r\n')
        emitter.emit(iostream)
        assert MockMTGraphiteClient.call_count == 1
