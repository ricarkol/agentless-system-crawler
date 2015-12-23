import  elasticsearch 
import elasticsearch.client
from elasticsearch.helpers import bulk, streaming_bulk
from elasticsearch_dsl import Search, Q
import json

query_template= '''
        {"query":
            { "bool":{
                "must":[
                    { "match_phrase_prefix": { "namespace.raw" : "%s" } },
                    { "match": { "uuid" : "%s" } }
                ]
            }
         }
      }
        '''
class IndexClient(object):

    def __init__(self, elastic_host):
        self.es = elasticsearch.Elasticsearch([elastic_host])

    def get_result_count(self, namespace, uuid, index_name, doc_type):

        try:
            result_query = query_template % (namespace, uuid)
            result = self.es.count(index=index_name, doc_type=doc_type, 
                body=result_query.replace("'", '"'), request_timeout=900)
            return int(result.get('count'))
        except elasticsearch.NotFoundError, e:
            raise
                 
