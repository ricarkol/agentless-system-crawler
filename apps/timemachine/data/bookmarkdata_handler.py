import elasticsearch
import json
import logging
import os
import sys

match_all = '"query": {"match_all": {}}'

tags_template= '''
    "query":
    {
        "terms" : {
            "tags" :  [ %s] 
        }
    }
'''
namespaces_template= '''
    "query":
    {
        "terms" : {
            "namespaces" : %s ,
            "minimum_should_match" : 1
        }
    }
'''
tags_and_namespaces_template = '''
    "query": {
        "bool" : {
            "must" : [
                {
                    "terms" : {
                        "tags" : %s,
                        "minimum_should_match" : 1
                    }
                },
                {
                    "terms" : {
                        "namespaces" : %s,
                        "minimum_should_match" : 1
                    }
                }
            ]
        }
    }
'''

#namespace_template = '''
#      "aggs" : {
#        "namespaces" : {
#          "terms" : { "field" : "namespace.raw", "size":0}
#        }
#      }
#'''
namespace_template = '''
      "aggs" : {
        "namespaces" : {
          "terms" : { "field" : "namespace.raw", "size":0}
        },
         "aggs": { "avail_times": { "terms": {"field": "timestamp", "size":0}}}
      }
'''
duration_filtered = '''
{
    "query": {
        "filtered":{ %s
        ,
        "filter": {
            "range": {
                "@timestamp": {"gte":"%s", "lte": "%s"}
            }
        }
     }
  }
}
'''

begin_filtered = '''
{
    "query": {
        "filtered":{ %s
        ,
        "filter": {
            "range": {
                "@timestamp": {"gte":"%s"}
            }
        }
     }
  }
}
'''
end_filtered = '''
{
    "query": {
        "filtered":{ %s
        ,
        "filter": {
            "range": {
                "@timestamp": {"lte":"%s"}
            }
        }
     }
  }
}
'''

logger = logging.getLogger("cloudsight.timemachine")

CONFIG_INDEX_PREFIX = 'config-'
CONFIG_DOC_TYPE = 'config_crawler'

class NamespaceHandler(object):

    def __init__(self, es_cluster):
        self.es_cluster = es_cluster
        self.es = elasticsearch.Elasticsearch(hosts=self.es_cluster)

    def _get_query(self, begin_time=None, end_time=None):

        if begin_time and end_time:
            return duration_filtered % (namespace_template, begin_time, end_time)
        elif begin_time:
            return begin_filtered % (namespace_template, begin_time)
        elif end_time: 
            return end_filtered % (namespace_template, end_time)
        else:
            return "{ %s } " % namespace_template

    def get_namespaces(self, begin_time=None, end_time=None):
        index = '_all'
        if bool(begin_time) and bool(end_time):
            index1 = util.datetime.get_index_from_iso_timestamp(begin_time, CONFIG_INDEX_PREFIX)
            index2 = util.datetime.get_index_from_iso_timestamp(end_time, CONFIG_INDEX_PREFIX)
            index = '%s,%s' % (index1, index2)
        logger.debug('get_namespaces: searching against index(es) "%s"' % index)
        result = self.es.search(index=index, doc_type=CONFIG_DOC_TYPE, body=self._get_query(begin_time, end_time))
        logger.debug('get_namespaces: Search time: %s ms' % result['took'])
        if result['hits']['total'] == 0:
            return []

        if bool(begin_time) and bool(end_time):
            namespaces = [ x['key'] for x in result['aggregations']['filtered_namespaces']['namespaces']['buckets'] ]
        else:
            namespaces = [ x['key'] for x in result['aggregations']['namespaces']['buckets'] ]
        logger.debug('get_namespaces: Found the following namespaces: "%s"' % namespaces)

        return namespaces

class BookmarkDataHandler(object):

    def __init__(self, es_cluster):
        self.es_cluster = es_cluster
        self.es = elasticsearch.Elasticsearch(hosts=self.es_cluster)
        self.index = "bookmark"
        self.doc_type = "bookmark"

    def _get_query(self, tags=None, namespaces=None, begin_time=None, end_time=None):

        if tags and  namespaces: 
           inner_query = tags_and_namespaces_template % (json.dumps(tags), json.dumps(namespaces))
        elif tags:
           inner_query = tags_template % json.dumps(tags)
        elif namespaces:
           inner_query = namespaces_template % json.dumps(namespaces)
        else:
            inner_query = match_all

        if begin_time and end_time:
            return duration_filtered % (inner_query, begin_time, end_time)
        elif begin_time:
            return begin_filtered % (inner_query, begin_time)
        elif end_time: 
            return end_filtered % (inner_query, end_time)
        else:
            return "{ %s } " % inner_query
        

    def get_bookmarks(self, tags=None, namespaces=None, begin_time=None, end_time=None):
        logger.debug('get_bookmarks:tags={}, namespaces={}, begin_time={}, end_time={}'.format(tags, namespaces, begin_time, end_time))
        query = self._get_query(tags, namespaces, begin_time, end_time)
        logger.debug('get_bookmark: query={}'.format(query))
        res = self.es.search(index=self.index, body=query, size=1000000)

        results = []
        if res['hits']['total'] == 0:
            return results

        for hit in res['hits']['hits']:
            r = hit['_source']
            r['_id'] = hit['_id']
            results.append(r)

        logger.debug('get_bookmarks: results={}'.format(json.dumps(results, indent=2)))
        return results

    def delete_bookmark(self, doc_id ):
        logger.debug('delete_bookmark:doc_id={}'.format(doc_id))
        res = self.es.delete(index=self.index, doc_type=self.doc_type, id=doc_id)
        logger.debug('delete_bookmark: resp={}'.format(res))
        
    def create_bookmark(self, bookmark, doc_id=None):
        logger.debug('elastic search: {}'.format(self.es.info()))
        logger.debug('create_bookmark: {}'.format(bookmark))
        return self.es.index(index=self.index, doc_type=self.doc_type, id=doc_id, body=bookmark)

    def clear_all(self):
        res = self.es.delete_by_query(index=self.index, body={"query": {"match_all": {}}})

    def get_bookmark(self, doc_id):
        logger.debug('get_bookmark: {}'.format(doc_id))
        try:
            res = self.es.get(index=self.index, id=doc_id)
            result = res['_source']
            result['_id'] = res['_id']
            logger.debug(result)
            return  result
        except elasticsearch.exceptions.NotFoundError, e:
            logger.error('get_bookmark: {}: {}'.format(e,doc_id))
            raise

if __name__ == '__main__':
    _my_dir = os.path.abspath(os.path.dirname(sys.argv[0]))
    _base_dir = os.path.abspath(os.path.join(_my_dir, '..')) 
    sys.path.append(_base_dir)

    logger.setLevel(logging.DEBUG)
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s: %(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)

    esc = 'demo3.sl.cloud9.ibm.com:9200'
    tags = ['wget', 'nginx']
    ns = ['server1', 'srv1']
    begin_time = "2015-01-26T09:00:00-0400"
    end_time = "2015-01-26T09:30:00-0400"
    tn = tags_and_namespaces_template % (json.dumps(tags), json.dumps(ns))
    
    #bh = BookmarkHandler(esc)
    #print bh.get_bookmarks()
    #print bh.get_bookmarks(tags=tags)
    #print bh.get_bookmarks(namespaces=ns)
    #print bh.get_bookmarks(tags=tags,namespaces=ns)
    #print bh.get_bookmarks(begin_time=begin_time)
    #print bh.get_bookmarks(tags=tags, begin_time=begin_time)
    #print bh.get_bookmarks(namespaces=ns, begin_time=begin_time, end_time=end_time)
    #print bh.get_bookmarks(tags=tags, namespaces=ns, begin_time=begin_time, end_time=end_time)
    #print bh.get_bookmarks(tags=tags,namespaces=ns)

    nh = NamespaceHandler(esc)
    nh.get_namespaces()
