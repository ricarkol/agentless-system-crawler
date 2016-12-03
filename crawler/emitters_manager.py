#!/usr/bin/python
# -*- coding: utf-8 -*-
import cStringIO
import json
import logging
import time
import urlparse

from base_crawler import BaseFrame
from plugins.emitters.file_emitter import FileEmitter
from plugins.emitters.http_emitter import HttpEmitter
from plugins.emitters.kafka_emitter import KafkaEmitter
from plugins.emitters.stdout_emitter import StdoutEmitter
from plugins.emitters.mtgraphite_emitter import MtGraphiteEmitter
from crawler_exceptions import (EmitterUnsupportedFormat,
                                EmitterUnsupportedProtocol)

logger = logging.getLogger('crawlutils')


class EmittersManager:
    """
    Class that stores a list of emitter objects, one for each url. This class
    should be instantiated at the beginNing of the program, and emit() should
    be called for each frame. emit() calls the emit() function of each emitter
    object.  This class can also emit() frames in different formats, for
    example in json format, each feature in a frame is a json.
    """

    proto_to_class = {
        'stdout': {'csv': {'class': StdoutEmitter, 'per_line': False},
                   'graphite': {'class': StdoutEmitter, 'per_line': False},
                   'json': {'class': StdoutEmitter, 'per_line': False},
                   },
        'file': {'csv': {'class': FileEmitter, 'per_line': False},
                 'graphite': {'class': FileEmitter, 'per_line': False},
                 'json': {'class': FileEmitter, 'per_line': False},
                 },
        'http': {'csv': {'class': HttpEmitter, 'per_line': False},
                 'graphite': {'class': HttpEmitter, 'per_line': False},
                 'json': {'class': HttpEmitter, 'per_line': True},
                 },
        'kafka': {'csv': {'class': KafkaEmitter, 'per_line': False},
                  'graphite': {'class': KafkaEmitter, 'per_line': False},
                  'json': {'class': KafkaEmitter, 'per_line': True},
                  },
        'mtgraphite': {'graphite': {'class': MtGraphiteEmitter,
                                    'per_line': True},
                       },
    }

    def __init__(
        self,
        urls,
        format='csv',
        compress=False,
        extra_metadata={}
    ):
        """
        Initializes a list of emitter objects; also stores all the args.

        :param urls: list of URLs to send to
        :param format: format of each feature string
        :param compress: gzip each emitter frame or not
        :param extra_metadata: dict added to the metadata of each frame
        """
        self.extra_metadata = extra_metadata
        self.urls = urls
        self.compress = compress
        self.format = format

        # Create a list of Emitter objects based on the list of passed urls
        self.emitters = []
        for url in self.urls:
            self.allocate_emitter(url)

    def allocate_emitter(self, url):
        parsed = urlparse.urlparse(url)
        proto = parsed.scheme
        if proto not in self.proto_to_class:
            raise EmitterUnsupportedProtocol('Not supported: %s' % proto)
        if self.format not in self.proto_to_class[proto]:
            raise EmitterUnsupportedFormat('Not supported: %s' % self.format)
        emitter_class = self.proto_to_class[proto][self.format]['class']
        emit_per_line = self.proto_to_class[proto][self.format]['per_line']
        emitter = emitter_class(url, emit_per_line=emit_per_line)
        self.emitters.append(emitter)

    def emit(self, frame, snapshot_num=0):
        """
        Sends a frame to the URLs specified at __init__

        :param frame: frame of type BaseFrame
        :param snapshot_num: iteration count (from worker.py). This is just
        used to differentiate successive frame files (when url is file://).
        :return: None
        """
        if not isinstance(frame, BaseFrame):
            raise TypeError('frame is not of type BaseFrame')

        metadata = frame.metadata
        metadata.update(self.extra_metadata)

        iostream = cStringIO.StringIO()

        if self.format == 'csv':
            self.write_in_csv_format(iostream, frame)
        elif self.format == 'json':
            self.write_in_json_format(iostream, frame)
        elif self.format == 'graphite':
            self.write_in_graphite_format(iostream, frame)

        # Pass iostream to the emitters so they can sent its content to their
        # respective url
        for emitter in self.emitters:
            emitter.emit(iostream, self.compress,
                         metadata, snapshot_num)

    def write_in_csv_format(self, iostream, frame):
        iostream.write('%s\t%s\t%s\n' %
                       ('metadata', json.dumps('metadata'),
                        json.dumps(frame.metadata, separators=(',', ':'))))
        for (key, val, feature_type) in frame.data:
            if not isinstance(val, dict):
                val = val._asdict()
            iostream.write('%s\t%s\t%s\n' % (
                feature_type, json.dumps(key),
                json.dumps(val, separators=(',', ':'))))

    def write_in_json_format(self, iostream, frame):
        iostream.write('%s\n' % json.dumps(frame.metadata))
        for (key, val, feature_type) in frame.data:
            if not isinstance(val, dict):
                val = val._asdict()
            val['feature_type'] = feature_type
            val['namespace'] = frame.metadata.get('namespace', '')
            iostream.write('%s\n' % json.dumps(val))

    def write_in_graphite_format(self, iostream, frame):
        namespace = frame.metadata.get('namespace', '')
        for (key, val, feature_type) in frame.data:
            if not isinstance(val, dict):
                val = val._asdict()
            self.write_feature_in_graphite_format(iostream, namespace,
                                                  key, val, feature_type)

    def write_feature_in_graphite_format(self, iostream, namespace,
                                         feature_key, feature_val,
                                         feature_type):
        """
        Write a feature in graphite format into iostream.

        :param namespace:
        :param feature_type:
        :param feature_key:
        :param feature_val:
        :param iostream: a CStringIO used to buffer the formatted features.
        :return:
        """
        timestamp = time.time()
        items = feature_val.items()
        namespace = namespace.replace('/', '.')

        for (metric, value) in items:
            try:
                # Only emit values that we can cast as floats
                value = float(value)
            except (TypeError, ValueError):
                continue

            metric = metric.replace('(', '_').replace(')', '')
            metric = metric.replace(' ', '_').replace('-', '_')
            metric = metric.replace('/', '_').replace('\\', '_')

            feature_key = feature_key.replace('_', '-')
            if 'cpu' in feature_key or 'memory' in feature_key:
                metric = metric.replace('_', '-')
            if 'if' in metric:
                metric = metric.replace('_tx', '.tx')
                metric = metric.replace('_rx', '.rx')
            if feature_key == 'load':
                feature_key = 'load.load'
            feature_key = feature_key.replace('/', '$')

            tmp_message = '%s.%s.%s %f %d\r\n' % (namespace, feature_key,
                                                  metric, value, timestamp)
            iostream.write(tmp_message)