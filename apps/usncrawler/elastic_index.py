import  elasticsearch 
import elasticsearch.client
from elasticsearch.helpers import bulk, streaming_bulk
from elasticsearch_dsl import Search, Q
import json


ELASTIC_SEARCH_HOST = 'http://demo3.sl.cloud9.ibm.com:9200'
TEMPLATE_FILE_NAME = 'index_template.json'
TEMPLATE_NAME = 'security_notices_template'
INDEX_NAME = 'security_notices'
DOC_TYPE = 'security_notice'
usn_fields = ['id', 'url', 'fixdata', 'summary' ]

class Index(object):

    def __init__(self, elastic_host):
        self.es = elasticsearch.Elasticsearch([elastic_host])
        self.index_client = elasticsearch.client.IndicesClient(self.es)

    def _put_template(self, template_file, logger):
        with open(template_file, 'r') as fp:
            template_body = fp.read()
            result = self.index_client.put_template(name=TEMPLATE_NAME, body=template_body)
            logger.info(json.dumps(result))

    def _get_template(self):
        result = self.index_client.get_template(name=TEMPLATE_NAME)
        print json.dumps(result, indent=2)

    def _delete_template(self):
        result = self.index_client.delete_template(name=TEMPLATE_NAME)
        print json.dumps(result, indent=2)

    def _create_index(self, logger):
        result = self.index_client.create(index=INDEX_NAME)
        logger.info (json.dumps(result))

    def _delete_index(self):
        result = self.index_client.delete(index=INDEX_NAME)
        print json.dumps(result, indent=2)

    def _get_index_info(self):
        result = self.index_client.get(index=INDEX_NAME,feature="_settings")
        print json.dumps(result, indent=2)

    def _get_field_mappings(self):
        result = self.index_client.get_field_mapping(index=INDEX_NAME, doc_type=DOC_TYPE, field=",".join(usn_fields))
        print json.dumps(result, indent=2)

    def _get_index_stats(self):
        result = self.index_client.stats(index=INDEX_NAME, metric="_all")
        print json.dumps(result, indent=2)

    def load_index(self, usn_info_list, logger):

        logger.info("secure_notices count={}".format(len(usn_info_list)))
        if not self.index_client.exists_template(name=TEMPLATE_NAME):
            self._put_template('./'+TEMPLATE_FILE_NAME, logger)

        if not self.index_client.exists(index=INDEX_NAME):
            self._create_index(logger)

        # drop documents which have usnid, instead of id
        docs_with_id = [doc for doc in usn_info_list if 'id' in doc] 
        for doc in docs_with_id: 
            doc['_id'] = doc['id']

        for ok, result in streaming_bulk(
                self.es,
                docs_with_id,
                index=INDEX_NAME,
                doc_type=DOC_TYPE,
                chunk_size=500 # keep the batch sizes small for appearances only
            ):
                action, result = result.popitem()
                doc_id = '/%s/%s/%s' % (INDEX_NAME, DOC_TYPE, result['_id'])
                if not ok:
                    logger.error('Failed to %s document %s: %r' % (action, doc_id, result))
                else:
                    logger.info('security notice successfully loaded: %s' % result['_id'])

        logger.info("indexing into elastic search complete")

    def get_all_usn(self):

        all_usn_query= '''
        {
            "query": {
                "match_all": {}
            }
        }
        '''
        scroll_result = self.es.search(index=INDEX_NAME, doc_type=DOC_TYPE, search_type='scan',
             body=all_usn_query.replace("'", '"'), scroll="1m", request_timeout=900, size=5000)

        scroll_id = scroll_result['_scroll_id']
        total_docs = scroll_result['hits']['total']
        n_docs = 0
        usn_info_list = []
        while n_docs < total_docs:
            results = self.es.scroll(scroll_id=scroll_id, scroll="1m", request_timeout=600)
            scroll_id = results['_scroll_id']
            n_docs += len(results['hits']['hits']) # Number of documents returned
            for doc in results['hits']['hits']:
                usn_info_list.append(doc['_source'])

        return usn_info_list
                 

if __name__ == '__main__':

    usn_index = Index(elastic_host=ELASTIC_SEARCH_HOST)

    #usn_index.get_os_feature()
    #usn_index.create_index()
    #usn_index.get_index_info()
    #usn_index.get_index_stats()
    #usn_index.count_by_aggregation_crawlinfo()
    #usn_index.count_by_aggregation()
    #template_file='/Users/sastryduri/tmp/index-template.json'
    #usn_index.put_template(template_file)
    usn_index._delete_index()
    #usn_index.get_field_mappings()

    #usn_index.put_template('./'+TEMPLATE_FILE_NAME)
    #usn_index.get_template();
    #usn_index.delete_template()
    #with open('./usninfos.json','r') as fp:
    #   usn_info_list  = json.load(fp)
    #   usn_index.load_index(usn_info_list)
    #usn_index.get_all_usn()
