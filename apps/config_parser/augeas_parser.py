#!/usr/bin/env python

'''
@author: Nilton Bila
(c) IBM Research 2015
'''

import os
import augeas
import config_store
import time
import sys
import re
import urlparse
import errno
import signal
from functools import wraps

FTYPE_AUGEAS = 'configparam'
FTYPE_CONFIG = 'config'
FTYPE_USER   = 'user'
FTYPE_GROUP  = 'group'
CONFIG_ROOT  = '/tmp/augeas'
LENSES_DIR   = 'share/augeas/lenses/dist/'
USER_FILE    = ['/etc/passwd']
GROUP_FILE   = ['/etc/group']
TIMEOUT      = 180
        
class TimeoutError(Exception):
    pass

def timeout(seconds=5, msg=os.strerror(errno.ETIMEDOUT)):
    def decorator(func):
        def timeout_handler(sig, frame):
            raise TimeoutError(msg)

        def wrapper(*args, **kwargs):
            signal.signal(signal.SIGALRM, timeout_handler)
            signal.alarm(seconds)
            try:
                ret = func(*args, **kwargs)
            finally:
                signal.alarm(0)
            return ret

        return wraps(func)(wrapper)

    return decorator

class AugeasParser():
    def __init__(self, logger, suppress_comments=True):
        self.lenses_dir   = LENSES_DIR
        self.config_store = config_store.ConfigStore(CONFIG_ROOT)
        self.suppress_comments = suppress_comments
        self.augsafe_re   = re.compile(r'([!=,\[\]\(\)])')
        self.comments_re  = re.compile("#comment(\[[0-9]+\])?$")
        self.logger       = logger
        sys.setrecursionlimit(50)

    @timeout(TIMEOUT)
    def parse_file(self, roots, augeas_instance, annotations, feature_key):
        self.walkTree(roots, augeas_instance, annotations, feature_key)

    def parse_update(self, feature_data, known_config_files=(), request_id='unknown', namespace='unknown'):
        self.match_time = 0
        self.get_time = 0
        walking_time = 0
        search_time = 0
        start_time = time.time()
        
        
        system_dirname = self.config_store.create_temp_system_store()
        system_root = os.path.join(CONFIG_ROOT, system_dirname)
                        
        feature_keys = []

        self.logger.debug("%s: namespace=%s, features=%d, known_config_files=%s" % \
                        (request_id, namespace, len(feature_data), str(known_config_files)))

        for feature_type, feature_key, value in feature_data:
            if feature_type != FTYPE_CONFIG:
                continue
            
            elif len(known_config_files) == 0 or feature_key in known_config_files:
                try:
                    self.config_store.create_file(system_dirname, 
                                                  str(feature_key), 
                                                  value['content'])
                except TypeError, e:
                    self.logger.warn("%s: Bad data format for config feature '%s': %s" % (request_id, feature_key, str(e)))
                
                feature_keys.append(feature_key)
            else:
                self.logger.debug("%s: %s not in list of known_config_files" % (request_id, feature_key))

        self.logger.info("%s: Parsing %d config files in %s" % \
                        (request_id, len(feature_keys), namespace))
          
                        
        fscreate_time = time.time()
            
        augeas_instance = augeas.Augeas(root=system_root, loadpath=self.lenses_dir)
        
        tree_time = time.time()
        
        generic_lenses = [
                            ('Xml', 'XmlGeneric'),                     #xml files
                            ('MySQL', 'IniFileGeneric'),               #ini files
                            ('Json', 'JsonGeneric'),                   #json files
                            ('Shellvars', 'ShellvarsGeneric'),         #shell variables
                            ('Phpvars', 'PhpvarsGeneric'),             #php variables
                            ('Properties', 'PropertiesGeneric'),       #java properties files
                            ('Httpd', 'HttpdGeneric'),                 #non-standard httpd installs
                            ('Spacevars', 'SpacevarsGeneric'),         #param val, e.g. Redis
                            ('ColonEqualSep', 'ColonEqualSepGeneric'), #param = val, param: val
                        ]

        annotations = []
        unparsed_keys = []
        for feature_key in feature_keys:
            try:
                feature_key = str(feature_key)
                spath = feature_key
                if spath[0] == '/':
                    spath = spath[1:]
                roots = augeas_instance.match(os.path.join('/files', spath))
                        
            except RuntimeError, e:
                self.logger.error("%s: Error parsing config file %s" % \
                                       (request_id, feature_key))
                continue
            
            if len(roots) == 0:
                unparsed_keys.append((feature_key, spath))
            else:
                self.logger.debug("%s: Parsing config file %s with default lens" % \
                                       (request_id, feature_key)) 
                
                walk_start = time.time()
                try:
                    self.parse_file(roots, augeas_instance, annotations, feature_key)
                except TimeoutError, e:
                    self.logger.warn("%s: Timeout exceeded while parsing file %s" % \
                                          (request_id, feature_key))
                except Exception, e:
                    self.logger.error("%s: Runtime error while walking %s tree: %s" % 
                                          (request_id, feature_key, e))
                walking_time += (time.time() - walk_start)
            
        #now parse files w/o explicit lenses
        for feature_key, spath in unparsed_keys:
            start = time.time()
            for lens, name in generic_lenses:
                augeas_instance.clear_transforms()
                augeas_instance.add_transform(lens, (feature_key), name=name)
                augeas_instance.load()
                roots = augeas_instance.match(os.path.join('/files', spath))
                if len(roots):
                    self.logger.debug("%s: Found lens '%s' for feature %s" % \
                                          (request_id, lens, feature_key))
                    break
            search_time += time.time() - start
                
            if len(roots) == 0:
                self.logger.warning("%s: No lens matching config file %s" % \
                                        (request_id, feature_key))
            else:
                self.logger.debug("%s: Parsing config file %s with fallback lens" % \
                                       (request_id, feature_key))
                
                walk_start = time.time()
                try:
                    self.parse_file(roots, augeas_instance, annotations, feature_key)
                except TimeoutError, e:
                    self.logger.warn("%s: Timeout exceeded while parsing file %s" % \
                                         (request_id, feature_key))
                except Exception, e:
                    self.logger.error("%s: Runtime error while walking %s tree: %s" % \
                                         (request_id, feature_key, e))
                    
                walking_time += (time.time() - walk_start)
                        
                    
        parse_time = time.time()
        
        #url parsing heuristics
        uris = self.parse_urls(annotations)
        annotations.extend(uris)
        urlparsing_time = time.time()
        
        self.config_store.remove_system_store(system_dirname)
        augeas_instance.close()
    
        teardown_time = time.time()
        stats = {
                "fs_creation": fscreate_time - start_time, 
                 "tree_build": tree_time - fscreate_time,
                 "lens_search": search_time,
                 "walking": walking_time,
                 "url_parsing": urlparsing_time - parse_time,
                 "teardown": teardown_time - urlparsing_time,
                 "lens_time": parse_time - tree_time - walking_time - search_time,
                 "match_time": self.match_time, 
                 "get_time": self.get_time,
                 "total_time": teardown_time - start_time
                }
        self.logger.info("%s: Performance stats for namespace %s: %s" % \
                              (request_id, namespace, str(stats)))
        
        return annotations
                
    def walkTree(self, roots, augeas_instance, annotations, feature_key, lens=None):
        if feature_key in USER_FILE:
            ftype = FTYPE_USER
        elif feature_key in GROUP_FILE:
            ftype = FTYPE_GROUP
        else:
            ftype = FTYPE_AUGEAS
                
        for root in roots:
            try:
                if ftype != FTYPE_AUGEAS:
                    self.addUsers(root, augeas_instance, annotations, feature_key, ftype)
                else:
                    self.addChildren(root, augeas_instance, annotations, feature_key, lens)
            except RuntimeError, e:
                self.logger.error("Error parsing file %s: %s" % (feature_key, str(e)))
            
                
    def escapePath(self, path):
        spath = path 
        for char in set(self.augsafe_re.findall(spath)):
            spath = re.sub(r'(\%s)' % char, r'\\\1', spath)
        return spath
    
    def parsePhpvars(self, value):
        unquote_re = re.compile('^"(.+)"$')

        content = value.rstrip()
        content = content.rstrip(';')
        if unquote_re.search(content):
            content = unquote_re.sub(r"\1", content)
            
        return content
                    
    def addChildren(self, root, augeas_instance, update, path, lens):
        start = time.time()
        
        children = None
        try:
            children = augeas_instance.match('%s/*' % root)
        except RuntimeError:
            #escape augeas regex characters
            root_safe = self.escapePath(root)
            try:
                children = augeas_instance.match('%s/*' % root_safe)
            except RuntimeError:
                self.logger.error('Error matching nodes under %s' % root)
                return
            
            
        self.match_time += (time.time() - start)
            
        for child in children:
            if child.replace(root, '') != '/.':
                self.addChildren(child, augeas_instance, update, path, lens)
            
        start = time.time()
        
        value = augeas_instance.get(root)
         
        self.get_time += (time.time() - start)
        key = root[len('/files'):]
        if value and not (self.suppress_comments and self.comments_re.search(key)):
            if lens == 'Phpvars':
                value = self.parsePhpvars(value)
                
            feature_value = {
                        'file' : path, 
                        'parameter': key.replace('%s/' % path, ''), 
                        'value': value
                    } 

            update.append((FTYPE_AUGEAS, key, feature_value))
            
    def addUsers(self, root, augeas_instance, update, feature_key, ftype):
        start = time.time()
        children = None
        try:
            children = augeas_instance.match('%s/*' % root)
        except RuntimeError:
            #escape augeas regex characters
            root_safe = self.escapePath(root)
            try:
                children = augeas_instance.match('%s/*' % root_safe)
            except RuntimeError, e:
                self.logger.error('Error matching nodes under %s' % root)
                return
        
        self.match_time += (time.time() - start)
        
        for child in children:
            self.addUser(child, augeas_instance, update, feature_key, ftype)
        
    
    def addUser(self, root, augeas_instance, update, path, ftype):
        int_attributes = ['uid', 'gid']
        
        start = time.time()
        
        user_re    = re.compile(r'^user(\[\d+])?$')
        children = None
        try:
            children = augeas_instance.match('%s/*' % root)
        except RuntimeError:
            #escape augeas regex characters
            root_safe = self.escapePath(root)
            try:
                children = augeas_instance.match('%s/*' % root_safe)
            except RuntimeError, e:
                self.logger.error('Error matching nodes under %s' % root)
                return
            
        self.match_time += (time.time() - start)
        
        user = root.split('/')[-1]
         
        get_time  = 0
            
        #user=syslog; user[1]=adm,user[2]=root
        user_dict = {ftype: user}
        if ftype == 'group':
            user_dict['users'] = []
            
        for child in children:
            label = child.split('/')[-1]
            start = time.time()
            value = augeas_instance.get(child)
            if ftype == 'group' and user_re.search(label):
                user_dict['users'].append(value)
            else:
                user_dict[label] = value
            if label in int_attributes:
                user_dict[label] = int(user_dict[label])
            get_time += (time.time() - start)
           
        update.append((ftype, user, user_dict))
        
        self.get_time += get_time
    
    def parse_urls(self, annotations):
        unquote_re = re.compile('^"(.+)"$')
        uris = []
        for ftype, fkey, value in annotations:
            try:
                if ftype == 'configparam' and value['value'][1:].find(':') > -1:
                    content = value['value'].rstrip()
            
                    if content[2:].find('://') > -1:
                        parsed = urlparse.urlparse(content)
                        #ParseResult(scheme='http', netloc='localhost:3306', path='/mydb', params='', query='', fragment='')
                        if parsed.scheme:
                            uris.append((ftype, fkey + '/scheme', {'parameter': value['parameter'] + '/scheme', 
                                                           'file': value['file'], 
                                                           'value': parsed.scheme}))
                    else:
                        parsed = urlparse.urlparse('scheme://' + content)
                        if not parsed.port and not parsed.path and not parsed.query:
                            continue 
                    if parsed.hostname:
                        uris.append((ftype, fkey + '/hostname', {'parameter': value['parameter'] + '/hostname', 
                                                             'file': value['file'], 
                                                             'value': parsed.hostname}))
                    if parsed.port:
                        uris.append((ftype, fkey + '/port', {'parameter': value['parameter'] + '/port', 
                                                         'file': value['file'], 
                                                         'value': parsed.port}))
                    if parsed.path:
                        uris.append((ftype, fkey + '/path', {'parameter': value['parameter'] + '/path', 
                                                         'file': value['file'], 
                                                         'value': parsed.path}))
                    if parsed.query:
                        uris.append((ftype, fkey + '/query', {'parameter': value['parameter'] + '/query', 
                                                         'file': value['file'], 
                                                         'value': parsed.query}))
                    if parsed.params:
                        uris.append((ftype, fkey + '/params', {'parameter': value['parameter'] + '/params', 
                                                             'file': value['file'], 
                                                             'value': parsed.params}))
                    if parsed.username:
                        uris.append((ftype, fkey + '/username', {'parameter': value['parameter'] + '/username', 
                                                             'file': value['file'], 
                                                             'value': parsed.username}))
                    if parsed.password:
                        uris.append((ftype, fkey + '/password', {'parameter': value['parameter'] + '/password', 
                                                             'file': value['file'], 
                                                             'value': parsed.password}))
                    if parsed.fragment:
                        uris.append((ftype, fkey + '/fragment', {'parameter': value['parameter'] + '/fragment', 
                                                             'file': value['file'], 
                                                             'value': parsed.fragment}))
            except ValueError:
                continue
        return uris



if __name__ == '__main__':
    parser = AugeasParser()
    print parser.parse_update(feature_data)
