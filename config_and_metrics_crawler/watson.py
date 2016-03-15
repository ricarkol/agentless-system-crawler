#!/usr/bin/python
# -*- coding: utf-8 -*-

import os
import json
import logging

logger = logging.getLogger('crawlutils')

def get_namespace(container_id, root_fs):
    with open(os.path.join(root_fs,'etc/csf_env.properties'),'r') as rp:
        namespace = None
        lines = dict([l.strip().split('=') for l in rp.readlines()])
        namespace = ".".join([lines[p[1:]].strip('\'') 
                    for p in lines.get('CRAWLER_METRIC_PREFIX',"").split(':')])
        if namespace:
            namespace += container_id
        return namespace

