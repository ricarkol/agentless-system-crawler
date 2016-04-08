#!/usr/bin/python
# -*- coding: utf-8 -*-

import os
import json
import logging
import copy

logger = logging.getLogger('crawlutils')

def get_namespace(long_id, options):
    assert type(long_id) is str or unicode, "long_id is not a string"
    assert 'host_namespace' in options
    assert 'root_fs' in options

    try:
        with open(os.path.join(options['root_fs'],'etc/csf_env.properties'),'r') as rp:
            namespace = None
            lines = {}
            for line in rp.readlines():
                line = line.strip()
                # strip preceeding export if exists
                if line.startswith('export'):
                    line = line[6:].strip() # len(export)=6
                parts = line.split('=')
                if len(parts) == 2:
                    lines[parts[0]] = parts[1]

            if 'CRAWLER_METRIC_PREFIX' not in lines:
                logger.error('CRAWLER_METRIC_PREFIX not found in /etc/csf_env.properties container id:' +
                      long_id);
                return

            prefix = lines['CRAWLER_METRIC_PREFIX']
            if prefix == '':
                return

            return options['host_namespace'].replace('/','.') + "." + prefix + '.' + long_id[:12]
    except IOError:
        logger.error('/etc/csf_env.properties not found in container with id:' +
                      long_id);

def get_log_file_list(long_id, options):
    assert type(long_id) is str or unicode, "long_id is not a string"
    assert 'root_fs' in options
    assert 'container_logs' in options

    container_logs = copy.deepcopy(options['container_logs'])
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
        logger.warning('/etc/logfiles not found in container with id:' +
                      long_id);
    return container_logs

def get_container_log_prefix(long_id, options):
    assert type(long_id) is str or unicode, "long_id is not a string"
    return get_namespace(long_id, options)
