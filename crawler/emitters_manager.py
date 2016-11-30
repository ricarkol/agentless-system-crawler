#!/usr/bin/python
# -*- coding: utf-8 -*-
import cStringIO
import json
import logging
import time

from base_crawler import BaseFrame
from emitters.file_emitter import FileEmitter
from emitters.http_emitter import HttpEmitter
from emitters.stdout_emitter import StdoutEmitter
from emitters.kafka_emitter import KafkaEmitter
from crawler_exceptions import (EmitterUnsupportedFormat)


logger = logging.getLogger('crawlutils')

class EmittersManager:
    """
    Class that stores a list of emitter objects, one for each url. This class
    should be instantiated at the beginNing of the program, and emit() should be
    called for each frame. emit() calls the emit() function of each emitter object.
    This class can also emit() frames in different formats, for example in json
    format, each feature in a frame is a json.
    """

    supported_formats = ['csv', 'graphite', 'json']

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

        if format not in self.supported_formats:
            raise TypeError('Emitter format not supported')

        self.extra_metadata = extra_metadata
        self.urls = urls
        self.compress = compress
        self.format = format

        self.emitters = []
        for url in self.urls:
            if url.startswith('stdout://'):
                self.emitters.append(StdoutEmitter(url))
            elif url.startswith('file://'):
                self.emitters.append(FileEmitter(url))
            elif url.startswith('http://'):
                self.emitters.append(HttpEmitter(url))
            elif url.startswith('kafka://'):
                self.emitters.append(KafkaEmitter(url))

    def emit(self, frame, snapshot_num):
        """
        Sends a frame to the URLs specified at __init__

        :param frame: frame of type BaseFrame
        :param snapshot_num: iteration count (from worker.py). This is just used
        to differentiate successive frame files (when url is file://).
        :return: None
        """
        if not isinstance(frame, BaseFrame):
            raise TypeError('frame is not of type BaseFrame')

        metadata = frame.metadata
        metadata.update(self.extra_metadata)

        iostream = cStringIO.StringIO()

        # write all features to iostream
        self.write_metadata(iostream, metadata)
        for (key, val, feature_type) in frame.data:
            self.write_feature(key, val, feature_type, iostream, metadata)

        # Pass iostream to the emitters so they can sent its content to their
        # respective url
        for emitter in self.emitters:
            emitter.emit(iostream, self.compress,
                              metadata, snapshot_num)

    def write_feature(
        self,
        feature_key,
        feature_val,
        feature_type=None,
        iostream=None,
        metadata={},
    ):
        """
        Write feature_key, feature_val, feature_type into iostream using the
        format in self.format.

        :param feature_key:
        :param feature_val:
        :param feature_type:
        :param iostream: a CStringIO stream used to buffer the formatted features.
        :param metadata: metadata dictionary of the Frame that has this
        feature being emitted.
        :return: None
        """
        if isinstance(feature_val, dict):
            feature_val_as_dict = feature_val
        else:
            feature_val_as_dict = feature_val._asdict()

        if self.format == 'csv':
            iostream.write('%s\t%s\t%s\n' % (
                feature_type,
                json.dumps(feature_key),
                json.dumps(feature_val_as_dict, separators=(',', ':'))))
        elif self.format == 'json':
            feature_val_as_dict['feature_type'] = feature_type
            feature_val_as_dict['namespace'] = metadata.get('namespace', '')
            iostream.write('%s\n' % json.dumps(feature_val_as_dict))
        elif self.format == 'graphite':
            namespace = metadata.get('namespace', '')
            self.write_in_graphite_format(
                namespace,
                feature_type,
                feature_key,
                feature_val_as_dict,
                iostream=iostream)
        else:
            raise EmitterUnsupportedFormat(
                'Unsupported format: %s' % self.format)

    def write_in_graphite_format(
        self,
        sysname,
        group,
        suffix,
        data,
        timestamp=None,
        iostream=None,
    ):
        """
        Write a feature in graphite format into iostream.

        :param sysname:
        :param group:
        :param suffix:
        :param data:
        :param timestamp:
        :param iostream: a CStringIO stream used to buffer the formatted features.
        :return:
        """
        timestamp = int(timestamp or time.time())
        items = data.items()
        sysname = sysname.replace('/', '.')

        for (metric, value) in items:
            try:
                # Only emit values that we can cast as floats
                value = float(value)
            except (TypeError, ValueError):
                continue

            metric = metric.replace('(', '_').replace(')', '')
            metric = metric.replace(' ', '_').replace('-', '_')
            metric = metric.replace('/', '_').replace('\\', '_')

            suffix = suffix.replace('_', '-')
            if 'cpu' in suffix or 'memory' in suffix:
                metric = metric.replace('_', '-')
            if 'if' in metric:
                metric = metric.replace('_tx', '.tx')
                metric = metric.replace('_rx', '.rx')
            if suffix == 'load':
                suffix = 'load.load'
            suffix = suffix.replace('/', '$')

            tmp_message = '%s.%s.%s %f %d\r\n' % (sysname, suffix,
                                                  metric, value, timestamp)
            iostream.write(tmp_message)

    def write_metadata(self, iostream, metadata):
        """
        Writes the metadata dictionary as a string into iostream.

        :param iostream: a CStringIO stream used to buffer the formatted features.
        :param metadata:
        :return:
        """
        # Update timestamp to the actual emit time
        metadata['timestamp'] = time.strftime('%Y-%m-%dT%H:%M:%S%z')
        if self.format == 'csv':
            iostream.write('%s\t%s\t%s\n' % ('metadata', json.dumps('metadata'),
                         json.dumps(metadata, separators=(',', ':'))))
        if self.format == 'json':
            iostream.write('%s\n' % json.dumps(metadata))
        # graphite format does not have a metadata feature as the namespace
        # is added at the beginning of every feature string.
