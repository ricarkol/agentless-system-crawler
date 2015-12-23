
import sys
try: import simplejson as json
except: import json
try: import cStringIO as StringIO
except: import StringIO
import shutil
import subprocess
import importlib
import tempfile
import zipfile
import csv
import os
import json
import pytz
import logging
from datetime import datetime
import protobuf_json
import requests
from cloudsight_types import CloudsightObjectFactory

DEFAULT_SCHEMA_URL = 'http://localhost:8082/schema/v0/type'

est = pytz.timezone("US/Eastern")
obj_factory = None
def add_feature(list_buf, feature_type, feature):

    global obj_factory

    def _toIso8601(time_value):
        p=est.localize(datetime.fromtimestamp(time_value)).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] 
        t=est.localize(datetime.fromtimestamp(time_value)).strftime("%z")
        return '%s%s:%s' %(p,t[0:3],t[3:])

    if feature_type == 'File':
        for k in ['atime', 'ctime', 'mtime']:
            if k in feature:
                feature[k] = _toIso8601(feature[k])

    msg_type =  obj_factory.getproto_type(feature_type)
    if msg_type:
        feature_buf=protobuf_json.json2pb(msg_type(), feature)
        list_buf.items.append(feature_buf.SerializeToString())
    else:
        print 'missing feature type:{}. ignoring feature.'.format(feature_type)

def encode_bookmark(bookmark, schema_url=DEFAULT_SCHEMA_URL, logger=None):

    global obj_factory

    if obj_factory is None:
        obj_factory = CloudsightObjectFactory(schema_url, logger)

    list_buffers = {} 

    try:
        f_type = 'Bookmark'
        if not f_type in list_buffers:
            list_type = obj_factory.getproto_type('List')
            if list_type is None:
                    sys.exit(1)
            list_buffers[fcap] = list_type()

        add_feature(list_buffers[f_type], f_type, bookmark)
    except Exception, e:
        if logger: logger.error("error encoding bookmark:".format(bookmark, str(e)))


    results = {}
    for ftype, feature_list_buf in list_buffers.iteritems():
        if feature_list_buf.ByteSize() == 0:
            continue
        # channel names are capitalized versions of type names
        results[ftype.capitalize()] = feature_list_buf.SerializeToString()

    return results

if __name__ == '__main__':
    app_logger = logging.getLogger("timemachine")
    app_logger.setLevel(logging.INFO)

    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(logging.INFO)
    formatter = logging.Formatter('%(asctime)s %(levelname)s %(lineno)4s: %(message)s')
    ch.setFormatter(formatter)
    app_logger.addHandler(ch)

    requests_log = logging.getLogger("requests")
    requests_log.setLevel(logging.WARNING)
    with open('/tmp/sout','r') as fp:
        data = fp.read()
        encode(data,{},schema_url, app_logger)
