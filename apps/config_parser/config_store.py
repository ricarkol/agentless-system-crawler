#!/usr/bin/env python

'''
@author: Nilton Bila
(c) IBM Research 2015
'''

import os
import tempfile
import shutil
import errno
import codecs

class ConfigStoreException(Exception):
    def __init__(self, message):
        self.message = message
        
    def __str__(self):
        return self.message

class ConfigStore():
    def __init__(self, config_root):
        self.config_root = config_root
        try:
            os.makedirs(self.config_root, mode=0700)
        except OSError, e:
            if e.errno != errno.EEXIST:
                raise e
            
    def create_system_store(self, system_id):
        path = self.absolute_path(system_id)
        if not self.path_in_dir(path, self.config_root):
            raise ConfigStoreException("system_id '%s'not allowed." % system_id)
        try:
            os.makedirs(path)
        except OSError, e:
            if e.errno != errno.EEXIST:
                raise e
            
    def create_temp_system_store(self):
        try:
            path = tempfile.mkdtemp(dir=self.config_root)
        except OSError, e:
            if e.errno != errno.EEXIST:
                raise e
        return os.path.basename(path)
        
    def remove_system_store(self, system_id):
        path = self.absolute_path(system_id)
        if not self.path_in_dir(path, self.config_root):
            raise ConfigStoreException("system_id '%s'not allowed." % system_id)
        try:
            shutil.rmtree(path)
        except OSError, e:
            if e.errno != errno.ENOENT:
                raise e
                        
    def read_file(self, system_id, local_path):
        file_path = self.absolute_path(system_id, local_path)
        if not self.path_in_dir(file_path, self.config_root):
            raise ConfigStoreException('Config file path %s/%s not within config root_dir %s' % \
                                     (system_id, file_path, self.config_root))
        if not os.path.isfile(file_path):
            raise ConfigStoreException('Config file path %s/%s does not match a regular file' % \
                                        (system_id, file_path))
        config_file = codecs.open(file_path, 'r', 'utf8')
        data = config_file.read()
        config_file.close()
        return data
        
    def create_file(self, system_id, local_path, data):
        file_path = self.absolute_path(system_id, local_path)
        if not self.path_in_dir(file_path, self.config_root):
            raise ConfigStoreException('Config file path %s/%s not within config root_dir %s' % \
                                (system_id, file_path, self.config_root))
        elif not os.path.exists(os.path.dirname(file_path)):
            os.makedirs(os.path.dirname(file_path), mode=0700)
        elif not os.path.isdir(os.path.dirname(file_path)):
            raise ConfigStoreException('Config file path %s/%s is not directory' % \
                                                 (system_id, os.path.dirname(file_path)))
        elif os.path.exists(file_path):
            if not os.path.isfile(file_path):
                raise ConfigStoreException('Config path %s/%s not regular file' % \
                                    (system_id, file_path))
            #else:
            #    self.logger.info('Overwriting config file %s/%s' % (system_id, file_path))
        
        config_file = codecs.open(file_path, 'w', encoding='utf8', errors='replace') 
        try:
            config_file.truncate(0)
            config_file.write(data)
        except Exception, e:
            raise e
        finally:
            config_file.close()
        
        return file_path
        
    def remove_file(self, system_id, local_path):
        file_path = self.absolute_path(system_id, local_path)
        if not self.path_in_dir(file_path, self.config_root):
            raise ConfigStoreException('Config file path %s/%s not within config root_dir %s' % \
                                        (system_id, file_path, self.config_root))
        if not os.path.isfile(file_path):
            raise ConfigStoreException('No config file was found at %s/%s' % (system_id, file_path))
        
        os.remove(file_path)
        
    def rename_file(self, system_id, old_path, new_path):
        src_path = self.absolute_path(system_id, old_path)
        dest_path = self.absolute_path(system_id, new_path)
        if not self.path_in_dir(src_path, self.config_root) or \
           not self.path_in_dir(dest_path, self.config_root):
            raise ConfigStoreException('Config file path %s/%s not within config root_dir %s' % \
                                        (system_id, dest_path, self.config_root))
        elif not os.path.exists(src_path):
            raise ConfigStoreException('Config source path %s/%s does not exist' % (system_id, src_path))
        elif not os.path.exists(os.path.dirname(dest_path)):
            os.makedirs(os.path.dirname(dest_path), mode=0700)
        elif not os.path.isdir(os.path.dirname(dest_path)):
            raise ConfigStoreException('Config destination path %s/%s is not directory' % \
                                                 (system_id, os.path.dirname(dest_path)))
        
        os.rename(src_path, dest_path)
        
        return dest_path

    def absolute_path(self, system_id, local_path = None):
        if local_path == None:
            return os.path.join(self.config_root, system_id)
        if local_path[0] == '/':
            local_path = local_path[1:]
        return os.path.join(os.path.join(self.config_root, system_id), local_path)
    
    def path_in_dir(self, path, dirname):
        return os.path.commonprefix([os.path.realpath(path), os.path.realpath(dirname)]) == \
            os.path.realpath(dirname)