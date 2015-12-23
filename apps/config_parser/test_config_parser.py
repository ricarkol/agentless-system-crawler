#!/usr/bin/env python
# -*- coding: utf-8 -*-

#!/usr/bin/env python

'''
@author: Nilton Bila
(c) IBM Research 2015
'''

import unittest
import augeas_parser
import logging
import csv
import sys
try:
    import simplejson as json
except:
    import json

test_frame = "test/config_frame.csv"

class ConfigParserTest(unittest.TestCase):
    def test_file_parsing(self):
        parser = augeas_parser.AugeasParser(logging, True)
        
        with file(test_frame) as fd:
            frame = []
            csv.field_size_limit(sys.maxsize) # required to handle large value strings
            csv_reader = csv.reader(fd, delimiter='\t', quotechar="'")
            for ftype, fkey, fvalue in csv_reader:
                frame.append((ftype, json.loads(fkey), json.loads(fvalue)))
            annotations = parser.parse_update(frame)
            
        user_tuple = ('user', 'root', {u'shell': u'/bin/bash', u'name': u'root', u'gid': 0, 'user': u'root', u'home': u'/root', u'password': u'x', u'uid': 0})
        group_tuple = ('group', 'root', {u'gid': 0, u'password': u'x', 'group': u'root', 'users': []})
        host_tuple = ('configparam', '/etc/hosts/1/ipaddr', {'parameter': u'1/ipaddr', 'value': u'172.17.0.90', 'file': '/etc/hosts'})
        
        self.assertEqual(86, len(annotations), "Expected 86 annotations, received %d instead.\n%s" % (len(annotations), annotations))
        self.assertEqual(user_tuple, annotations[0], "Expected first annotation: %s. \nReceived instead: %s" % (user_tuple, annotations[0]))
        self.assertEqual(group_tuple, annotations[22], "Expected first annotation: %s. \nReceived instead: %s" % (group_tuple, annotations[22]))
        self.assertEqual(host_tuple, annotations[70], "Expected first annotation: %s. \nReceived instead: %s" % (host_tuple, annotations[70]))
        
    
if __name__ == '__main__':
    unittest.main()
