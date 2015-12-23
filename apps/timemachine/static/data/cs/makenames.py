#!/bin/env python

import os, json

namespaces = {}
results = []
for f in os.listdir('j'):
    j = json.load(open(os.path.join('j',f),'r'))
    if j['crawl_times'] :
        results.append([f, j['crawl_times'][0]])

namespaces['namespaces'] = results
print json.dumps(namespaces, indent=2)
