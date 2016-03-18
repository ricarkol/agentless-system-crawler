#!/usr/bin/python
# -*- coding: utf-8 -*-

import os
import json
import logging

logger = logging.getLogger('crawlutils')

def get_namespace(long_id, options):
    assert type(long_id) is str or unicode, "long_id is not a string"
    assert 'root_fs' in options
    try:
        with open(os.path.join(options['root_fs'],'etc/csf_env.properties'),'r') as rp:
            namespace = None
            lines = dict([l.strip().split('=') for l in rp.readlines()])
            namespace = ".".join([lines[p[1:]].strip('\'') 
                        for p in lines.get('CRAWLER_METRIC_PREFIX',"").split(':')])
            if namespace:
                namespace = namespace + '.' + long_id[:16]
            return namespace
    except IOError:
        logger.error('/etc/csf_env.properties not found in container with id:' +
                      long_id);

def get_log_file_list(long_id, options):
    assert type(long_id) is str or unicode, "long_id is not a string"
    assert 'root_fs' in options
    assert 'container_logs' in options

    container_logs = options.get('container_logs', {})
    for log in container_logs:
        name = log['name']
        if not os.path.isabs(name) or '..' in name:
            container_logs.remove(log)
            logger.warning(
                'User provided a log file path that is not absolute: %s' %
                name)
    try:
        with open(os.path.join(options['root_fs'],'etc/logfiles'),'r') as rp:
            for l in rp.readlines():
                container_logs.append({'name': l.strip(), 'type': None})
    except IOError:
        logger.info('/etc/logfiles not found in container with id:' +
                      long_id);
    return container_logs

def get_container_log_prefix(long_id, options):
    assert type(long_id) is str or unicode, "long_id is not a string"
    return get_namespace(long_id, options)
