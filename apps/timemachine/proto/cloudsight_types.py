
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
import time

DEFAULT_SCHEMA_URL = 'http://localhost:8082/schema/v0/type'
class CloudsightObjectFactory(object):
    '''
    Serves python moudules for Cloudsight types.
    
    Fetches protobuf definitions from schema server, generates python modules using protoc compiler, and loads them.
    '''
    
    def __init__(self, schema_url, logger=None, fetch_wait=60):
        '''
        fetch_wait is specified as seconds
        '''
        self.schema_url = schema_url
        self.last_fetch_time = 0
        self.fetch_wait = 60 
        self.proto_modules = {}
        self.logger = logger

    def _import_proto_py(self):
    
        # download protozipfile from schema server
        try:
            r = requests.get(self.schema_url)
            if r.status_code != 200:
                self.logger.error('downloading protoc message definitions from schema server @{}, status_code={}'.format(
                                                self.schema_url, r.status_code))
                return 
            schemazip = r.content 
        except Exception, e:
            self.logger.error('_import_proto_py_1: {}:{}'.format(e, self.schema_url))
            return

        tdir = tempfile.mkdtemp() 
        zipdata = StringIO.StringIO(schemazip)
        try:
            with zipfile.ZipFile(zipdata, 'r') as myzip:
                myzip.extractall(tdir)
    
            for (dirpath, _, filenames) in os.walk(tdir, topdown=True):
                for pfile in filenames:
                    cmd = "/usr/local/bin/protoc --python_out={0} --proto_path={0} {1}/{2}".format(tdir, dirpath, pfile)
                    try:
                        subprocess.check_call(cmd.split())
                    except Exception, e:
                        self.logger.error('_import_proto_py: {}'.format(e))
                        return
    
            sys.path.insert(0,tdir) 
            for (dirpath, _, filenames) in os.walk(tdir, topdown=True):
                for pfile in filenames:
                    if pfile.endswith("pb2.py"):
                        feature_type = pfile.split('_')[0]
                        self.logger.warn('imporing feature_type {}'.format(feature_type))
                        self.proto_modules [feature_type] = importlib.import_module(pfile[:-3], package=tdir+'.')
    
            self.last_fetch_time = int(time.time());
        except Exception, e:
            self.logger.error('_import_proto_py_2: {}'.format(e))
        finally:
            try:
                shutil.rmtree(tdir)
            except Exception, e:
                self.logger.error('_import_proto_py_3 {}'.format(e))
            
    def getproto_type(self,feature_type):
        if feature_type not in self.proto_modules:
            if (int(time.time()) - self.last_fetch_time) < self.fetch_wait:
                self.logger.warn('skipping ftech due to non expiry of fetch_wait={} seconds for feature={}'.format(self.fetch_wait, feature_type))
                return None
            self._import_proto_py()
            if feature_type not in self.proto_modules:
                # we may see features without corresponding protobuf messages defined 
                return None   
        if feature_type == 'message': 
            return self.proto_modules[feature_type].List
        return getattr(self.proto_modules[feature_type],feature_type)
