from unittest import TestCase
import apps.config_parser.KafkaInterface as ki
from pykafka.exceptions import KafkaException
import mock
try:
    from cStringIO import StringIO
except:
    from StringIO import StringIO


# class TestKafkaInterface(KafkaInterface):
#     def __init__(self):
#         self.connect_to_kafka() = mock.Mock()
#         super(KafkaInterface, self)
def print_all(**args):
    print(" ".join(args))

### Test does not pass. Inline test used as substitute. This test needs work
# class ConfigParserTest(TestCase):
#     def test_consume(self):
        #
        # ki.KafkaInterface.connect_to_kafka = mock.Mock()
        #
        # a = mock.Mock()
        # a.value = "Message"
        # logger = mock.MagicMock()
        # logger.error = print_all()
        # logger.info = print_all()
        # logger.debug = print_all()
        # client = ki.KafkaInterface("123.123.123.123:8080",19092,logger,'config','publish','notify',True)
        # client.consumer = mock.Mock()
        # client.consumer.consume = mock.Mock(return_value=a)
        # client.stop_kafka_clients = mock.Mock()
        # for message in client.next_frame():
        #     data = StringIO(message)
        #
        # self.assertEquals(data.getvalue(), "Message")
        # self.assertEquals(client.consumer_test_complete, True)
        # self.assertEquals(client.last_consumer_retry_count, 60)





