import elasticsearch.client
import json
import prettytable
import datetime
import search.util.datetime_util
import search.logger
import feature_tables

class ConfigDataHandler:
    '''
    This class manipulates config crawler data indexed on Elasticsearch
    '''
    
    CONFIG_INDEX_PREFIX = 'config-'
    CONFIG_DOC_TYPE = 'config_crawler'
    
    SCROLL_TIME = '1m'
    SCROLL_BATCH_SIZE_PER_SHARD = 5000
    ELASTICSEARCH_REQUEST_TIMEOUT = 180
    
    CONFIG_FEATURES = ["file", "config", "process", "os", "disk", "connection", "package", "dockerps", "dockerinspect", "dockerhistory"]
    ALL_FEATURES = sorted(CONFIG_FEATURES + ["metric", "cpu", "memory", "load", "interface"])
    FEATURE_ID_FIELDS = ["feature_key", "feature_type", "key_hash", "contents_hash"]
    
    FILTERED_FILE_PATHS = [".log", ".dat", "workarea"]
    
    
    def __init__(self, es_client):
        '''
        Arguments:
          - 'es_client': An instance of elasticsearch.Elasticsearch.
        '''
        self.es_client = es_client
        self.indices_client = elasticsearch.client.IndicesClient(es_client)
    
    def get_namespaces(self, begin_time=None, end_time=None):
        '''
          Returns a list of all known namespaces within a time interval. If no time interval is given,
        the returned list of namespaces is not filtered by time.
          Arguments:
           - 'begin_time' (optional): String with an ISO8601 timestamp indicating the beginning of the time interval
           - 'end_time' (optional): String with an ISO8601 timestamp indicating the end of the time interval
        '''
        query_body = '''
{
  "_source": false,
  "query" : {
     "filtered": {
       "filter": {
         "range": {
           "timestamp": {"gte":"%s", "lte": "%s"}
         }
       }
     }
   },
  "aggs" : {
     "namespaces" : {
        "terms" : { "field" : "namespace.raw", "size":0}
     }
  }
}     
''' % (begin_time, end_time) if (begin_time and end_time) else '''
{
  "_source": false,
  "aggs" : {
     "namespaces" : {
        "terms" : { "field" : "namespace.raw", "size":0}
     }
  }
}
'''
        index = '_all'
        if bool(begin_time) and bool(end_time):
            #indices = search.util.datetime_util.get_indices_list_from_iso_timestamps(begin_time, end_time, ConfigDataHandler.CONFIG_INDEX_PREFIX)
            #existing_indices = self._get_existing_indices(indices)
            indices = self._get_indices(begin_time, end_time)
            if len(indices) == 0:
                return []
            index = ','.join(indices)
        search.logger.logger.debug('get_namespaces: Searching against index(es) "%s"' % index)
        result = self.es_client.search(index=index, doc_type=ConfigDataHandler.CONFIG_DOC_TYPE, search_type='count', 
                    body=query_body.replace("'", '"'), request_timeout=ConfigDataHandler.ELASTICSEARCH_REQUEST_TIMEOUT)
        search.logger.logger.debug('get_namespaces: Search time: %s ms' % result['took'])
        if result['hits']['total'] == 0:
            return []
        namespaces = [ x['key'] for x in result['aggregations']['namespaces']['buckets'] ]
        search.logger.logger.debug('get_namespaces: Found the following namespaces: "%s"' % namespaces)
        return sorted(namespaces)
    
    def get_frame(self, timestamp, namespace, features=[], search_type='closest', time_span_in_days=0.25, feature_to_key_map={}):
        '''
          Returns a logical frame (dictionary) encompassing all feature documents indexed as part of the same crawl.
        The timestamp provided by the user is used to determine what frame will be returned to the user. 
          Arguments:
          - 'timestamp': String with an ISO8601 timestamp
          - 'namespace': String representing the namespace identifying the source of the crawled features
          - 'features': Optional array of strings indicating the features that should be part of the logical frame. If
          the array is empty (default value), all config features that are indexed will be included in the returned
          logical frame.
          - 'search_type': Takes one of the following possible values: ['exact', closest']. If search_type is 'exact', this function
          looks for a logical frame with a crawl timestamp exactly matching the one given by the user; if searcg_type is 'closest', this
          function returns the logical frame closest to the given timestamp (either in the past or in the future). 
          - 'time_span_in_days': Defines the search scope of the search_type 'closest'. The scope will be this number of days 
          before and after the given timestamp. A float number can be used as this parameter, e.g., 0.5 (12 hours before and after the given
          timestamp).  
          - 'feature_to_key_map': Optional dictionary identifying, for each feature, the attribute that should be considered as the key
          when constructing the assembled logical frame. This overrides the key defined by the crawler.
        '''
        
        closest_crawl_timestamp = timestamp
        if search_type == 'closest':
            # Find the closest crawl timestamp that we know about
            closest_crawl_timestamp = self._get_closest_crawl_timestamp(namespace, timestamp, time_span_in_days)
            search.logger.logger.debug('get_frame: Closest crawl timestamp = %s' % closest_crawl_timestamp)
            if not closest_crawl_timestamp:
                # Could not find crawler data for the namespace, timestamp, and time span
                return {}
            closest_crawl_timestamp = search.util.datetime_util.validate_and_convert_timestamp(closest_crawl_timestamp)
        
        # Constructs the query to assemble a logical frame based on the closest_crawl_timestamp and the namespace
        if len(features) == 0:
            features = ConfigDataHandler.CONFIG_FEATURES
        query_body = self._get_query_to_assemble_frame(closest_crawl_timestamp, namespace, features)
        search.logger.logger.debug('get_frame: performing query <<< %s >>>' % query_body)
        
        # Determine what index we should search 
        index = search.util.datetime_util.get_index_from_iso_timestamp(closest_crawl_timestamp, ConfigDataHandler.CONFIG_INDEX_PREFIX)
        search.logger.logger.debug('get_frame: searching against index "%s"; search_type = %s' % (index, search_type))
        
        # Performs a scan/scroll query to retrieve all feature documents that comprise the logical frame
        scroll_results = self.es_client.search(index=index, doc_type=ConfigDataHandler.CONFIG_DOC_TYPE, body=query_body, 
                search_type='scan', scroll=ConfigDataHandler.SCROLL_TIME, size=ConfigDataHandler.SCROLL_BATCH_SIZE_PER_SHARD,
                request_timeout=ConfigDataHandler.ELASTICSEARCH_REQUEST_TIMEOUT)
        scroll_id = scroll_results['_scroll_id']
        total_docs = scroll_results['hits']['total']
        search.logger.logger.debug('get_frame: Scan operation --> scroll_id = %s -- Total number of documents = %d -- Query time: %d ms' % (scroll_id, total_docs, scroll_results['took']))
        n_docs = 0
        frame = {}
        if total_docs > 0:
            # Add the actual crawl timestamp to the frame
            frame['timestamp'] = closest_crawl_timestamp
        while n_docs < total_docs:
            results = self.es_client.scroll(scroll_id=scroll_id, scroll=ConfigDataHandler.SCROLL_TIME, request_timeout=ConfigDataHandler.ELASTICSEARCH_REQUEST_TIMEOUT)
            scroll_id = results['_scroll_id']
            n_docs += len(results['hits']['hits']) # Number of documents returned
            search.logger.logger.debug('get_frame: Scroll operation --> scroll_id = %s -- Number of docs returned so far = %d -- Query time: %d ms' % (scroll_id, n_docs, results['took']))
            # Iterates over the retrieved documents to construct the logical frame
            for doc in results['hits']['hits']:
                feature_key = doc['_source']['feature_key']
                feature_type = doc['_source']['feature_type']
                if bool(feature_to_key_map):
                    if feature_type in feature_to_key_map:
                        feature_key = doc['_source'][feature_type][feature_to_key_map[feature_type]]
                frame[feature_key] = doc['_source'][feature_type]
                frame[feature_key]['feature_type'] = feature_type
                frame[feature_key]['key_hash'] = doc['_source']['key_hash']
                frame[feature_key]['contents_hash'] = doc['_source']['contents_hash'] 
        return frame
    
    def get_frames(self, begin_time, end_time, namespace, features=[], feature_to_key_map=False):
        if len(features) == 0:
            features = ConfigDataHandler.CONFIG_FEATURES
        query_body = self._get_query_to_assemble_frames_list(begin_time, end_time, namespace, features)
        search.logger.logger.debug('get_frames: performing query <<< %s >>>' % query_body)
        indices = self._get_indices(begin_time, end_time)
        if len(indices) == 0:
            return {}
        index = ','.join(indices)
        search.logger.logger.debug('get_frames: Searching against index(es) "%s"' % index)
        
        # Performs a scan/scroll query to retrieve all feature documents that comprise all logical frames within the time interval
        scroll_results = self.es_client.search(index=index, doc_type=ConfigDataHandler.CONFIG_DOC_TYPE, body=query_body, 
                search_type='scan', scroll=ConfigDataHandler.SCROLL_TIME, size=ConfigDataHandler.SCROLL_BATCH_SIZE_PER_SHARD,
                request_timeout=ConfigDataHandler.ELASTICSEARCH_REQUEST_TIMEOUT)
        scroll_id = scroll_results['_scroll_id']
        total_docs = scroll_results['hits']['total']
        search.logger.logger.debug('get_frames: Scan operation --> scroll_id = %s -- Total number of documents = %d -- Query time: %d ms' % (scroll_id, total_docs, scroll_results['took']))
        n_docs = 0
        frames = {}
        while n_docs < total_docs:
            results = self.es_client.scroll(scroll_id=scroll_id, scroll=ConfigDataHandler.SCROLL_TIME, request_timeout=ConfigDataHandler.ELASTICSEARCH_REQUEST_TIMEOUT)
            scroll_id = results['_scroll_id']
            n_docs += len(results['hits']['hits']) # Number of documents returned
            search.logger.logger.debug('get_frames: Scroll operation --> scroll_id = %s -- Number of docs returned so far = %d -- Query time: %d ms' % (scroll_id, n_docs, results['took']))
            # Iterates over the retrieved documents to construct the logical frames
            for doc in results['hits']['hits']:
                timestamp = doc['_source']['timestamp']
                if not timestamp in frames:
                    frames[timestamp] = {}
                feature_key = doc['_source']['feature_key']
                feature_type = doc['_source']['feature_type']
                if bool(feature_to_key_map):
                    if feature_type in feature_to_key_map:
                        feature_key = doc['_source'][feature_type][feature_to_key_map[feature_type]]
                frames[timestamp][feature_key] = doc['_source'][feature_type]
                frames[timestamp][feature_key]['feature_type'] = feature_type
                frames[timestamp][feature_key]['key_hash'] = doc['_source']['key_hash']
                frames[timestamp][feature_key]['contents_hash'] = doc['_source']['contents_hash']
        if total_docs > 0:
            timestamp_list = sorted(frames.keys(), reverse=True)
            frames['timestamps'] = timestamp_list
        return frames
    
    def get_latest_frame(self, namespace, features=[]):
        if len(features) == 0:
            features = ConfigDataHandler.CONFIG_FEATURES
        query_body = '''
{
  "_source": false,
  "query" : {
     "filtered": {
       "filter": {
         "term": { "namespace.raw" : "%s" }
       }
     }
   },
  "aggs" : {
     "latest": {
         "max": {"field" : "timestamp"}
     }
  }
}
''' % namespace
        
        n_hits = 0
        index_iterator = self._index_iterator()
        while n_hits == 0:
            try:
                index = index_iterator.next()
                search.logger.logger.debug('get_latest_frame: Trying to get latest crawl timestamp for %s under index %s' % (namespace, index))
                result = self.es_client.search(index=index, doc_type=ConfigDataHandler.CONFIG_DOC_TYPE, search_type='count', 
                    body=query_body.replace("'", '"'), request_timeout=ConfigDataHandler.ELASTICSEARCH_REQUEST_TIMEOUT)
                n_hits = result['hits']['total']
            except StopIteration:
                # No data for the given namespace was found for the last 10 years
                return {}
        index_iterator.close()
        latest_crawl_time = result['aggregations']['latest']['value']
        latest_crawl_timestamp = datetime.datetime.utcfromtimestamp(latest_crawl_time/1000.0).isoformat() + 'Z'
        search.logger.logger.debug('get_latest_frame: Found latest crawl timestamp for %s: %s' % (namespace, latest_crawl_timestamp))
        latest_frame = self.get_frame(latest_crawl_timestamp, namespace, features, search_type='exact')
        return latest_frame
    
    def get_namespace_crawl_times(self, namespace, begin_time, end_time):
        query_body = '''
{
  "_source": false,
  "query" : {
     "filtered": {
       "filter": {
         "bool": {
           "must": [
             { "term": { "namespace.raw" : "%s" }},
             { "range": { "timestamp": {"gte":"%s", "lte": "%s" }}}
            ]
         }
       }
     }
  },
  "aggs" : {
     "timestamps" : {
        "terms" : { "field" : "timestamp", "size":0}
     }
  }
}
''' % (namespace, begin_time, end_time)
        indices = self._get_indices(begin_time, end_time)
        if len(indices) == 0:
            return []
        index = ','.join(indices)
        result = self.es_client.search(index=index, doc_type=ConfigDataHandler.CONFIG_DOC_TYPE, search_type='count', 
                    body=query_body.replace("'", '"'), request_timeout=ConfigDataHandler.ELASTICSEARCH_REQUEST_TIMEOUT)
        search.logger.logger.debug('get_namespace_crawl_times: Search time: %s ms' % result['took'])
        if result['hits']['total'] == 0:
            return []
        crawl_times = [ x['key_as_string'] for x in result['aggregations']['timestamps']['buckets'] ]
        search.logger.logger.debug('get_namespace_crawl_times: Found the following crawl times for namespaces %s: "%s"' % (namespace, crawl_times))
        return sorted(crawl_times, reverse=True)
    
    def get_raw_frame_diff_for_ui(self, begin_time, end_time, namespace, features=[]):
        begin_frame = self.get_frame(begin_time, namespace, features)
        end_frame = self.get_frame(end_time, namespace, features)
        begin_frame_keys = sorted(begin_frame.keys())
        begin_frame_keys.remove('timestamp')
        end_frame_keys= sorted(end_frame.keys())
        end_frame_keys.remove('timestamp')
        begin_frame_len = len(begin_frame_keys)
        end_frame_len = len(end_frame_keys)
        added = []
        modified = []
        deleted = []
        i = 0
        j = 0
        while i < begin_frame_len or j < end_frame_len:
            if i == begin_frame_len:
                #added.append(end_frame[end_frame_keys[j]])
                self._add_feature_to_ui_list(end_frame, end_frame_keys[j], added)
                j += 1
            elif j == end_frame_len:
                #deleted.append(begin_frame[begin_frame_keys[i]])
                self._add_feature_to_ui_list(begin_frame, begin_frame_keys[i], deleted)
                i += 1
            elif begin_frame_keys[i] < end_frame_keys[j]:
                #deleted.append(begin_frame[begin_frame_keys[i]])
                self._add_feature_to_ui_list(begin_frame, begin_frame_keys[i], deleted)
                i += 1
            elif begin_frame_keys[i] > end_frame_keys[j]:
                #added.append(end_frame[end_frame_keys[j]])
                self._add_feature_to_ui_list(end_frame, end_frame_keys[j], added)
                j += 1
            else:
                if self._is_modified(begin_frame[begin_frame_keys[i]], end_frame[end_frame_keys[j]]):
                    #modified.append(end_frame[end_frame_keys[j]])
                    self._add_feature_to_ui_list(end_frame, end_frame_keys[j], modified)
                i += 1
                j += 1
                
        frame_diff = {'added': added, 'deleted': deleted, 'modified': modified}
        search.logger.logger.debug('get_raw_frame_diff_for_ui: Diff = <<< %s >>>', json.dumps(frame_diff, indent=2)) 
        return frame_diff

    def get_raw_frame_diff(self, begin_time, end_time, namespace, features=[]):
        begin_frame = self.get_frame(begin_time, namespace, features)
        end_frame = self.get_frame(end_time, namespace, features)
        begin_frame_keys = sorted(begin_frame.keys())
        end_frame_keys= sorted(end_frame.keys())
        begin_frame_len = len(begin_frame_keys)
        end_frame_len = len(end_frame_keys)
        added = []
        modified = []
        deleted = []
        i = 0
        j = 0
        while i < begin_frame_len or j < end_frame_len:
            if i == begin_frame_len:
                #added.append(end_frame[end_frame_keys[j]])
                self._add_feature_to_list(end_frame, end_frame_keys[j], added)
                j += 1
            elif j == end_frame_len:
                #deleted.append(begin_frame[begin_frame_keys[i]])
                self._add_feature_to_list(begin_frame, begin_frame_keys[i], deleted)
                i += 1
            elif begin_frame_keys[i] < end_frame_keys[j]:
                #deleted.append(begin_frame[begin_frame_keys[i]])
                self._add_feature_to_list(begin_frame, begin_frame_keys[i], deleted)
                i += 1
            elif begin_frame_keys[i] > end_frame_keys[j]:
                #added.append(end_frame[end_frame_keys[j]])
                self._add_feature_to_list(end_frame, end_frame_keys[j], added)
                j += 1
            else:
                if self._is_modified(begin_frame[begin_frame_keys[i]], end_frame[end_frame_keys[j]]):
                    #modified.append(end_frame[end_frame_keys[j]])
                    self._add_feature_to_list(end_frame, end_frame_keys[j], modified)
                i += 1
                j += 1
                
        frame_diff = {'added': added, 'deleted': deleted, 'modified': modified}
        search.logger.logger.debug('get_raw_frame_diff: Diff = <<< %s >>>', json.dumps(frame_diff, indent=2)) 
        return frame_diff
    
    def get_frame_diff_report(self, frame_diff):
        added = self._group_frame_diff_by_feature_type(frame_diff, 'added')
        modified = self._group_frame_diff_by_feature_type(frame_diff, 'modified')
        deleted = self._group_frame_diff_by_feature_type(frame_diff, 'deleted')
#         for i in frame_diff['added']:
#             for singleton in frame_diff['added'][i].values():
#                 feature_type = singleton[0]['feature_type'] 
#                 if feature_type not in added:
#                     added[feature_type] = []
#                 added[feature_type].append(singleton[0])
        added_feature_tables = self._grouped_frame_diff_to_feature_tables(added)
        deleted_feature_tables = self._grouped_frame_diff_to_feature_tables(deleted)
        
        feature_tables_dict = {'added': added_feature_tables, 'deleted': deleted_feature_tables}
        search.logger.logger.debug('get_frame_diff_report: tables = <<< %s >>>', json.dumps(feature_tables_dict, indent=2))
        return feature_tables_dict
    
    def get_raw_namespace_diff(self, namespace1, time1, namespace2, time2, features):
        begin_frame = self.get_frame(time1, namespace1, features, feature_to_key_map={'process':'cmd'})
        end_frame = self.get_frame(time2, namespace2, features, feature_to_key_map={'process':'cmd'})
        #  TODO: When diffing different namespaces, we cannot rely on feature keys
        # for certain feature types, such as process. They may match, presumably, for packages and files/configs.
        begin_frame_keys = sorted(begin_frame.keys())
        end_frame_keys= sorted(end_frame.keys())
        begin_frame_len = len(begin_frame_keys)
        end_frame_len = len(end_frame_keys)
        added = []
        modified = []
        deleted = []
        i = 0
        j = 0
        while i < begin_frame_len or j < end_frame_len:
            if i == begin_frame_len:
                #added.append(end_frame[end_frame_keys[j]])
                self._add_feature_to_list(end_frame, end_frame_keys[j], added)
                j += 1
            elif j == end_frame_len:
                #deleted.append(begin_frame[begin_frame_keys[i]])
                self._add_feature_to_list(begin_frame, begin_frame_keys[i], deleted)
                i += 1
            elif begin_frame_keys[i] < end_frame_keys[j]:
                #deleted.append(begin_frame[begin_frame_keys[i]])
                self._add_feature_to_list(begin_frame, begin_frame_keys[i], deleted)
                i += 1
            elif begin_frame_keys[i] > end_frame_keys[j]:
                #added.append(end_frame[end_frame_keys[j]])
                self._add_feature_to_list(end_frame, end_frame_keys[j], added)
                j += 1
            else:
                if self._is_modified(begin_frame[begin_frame_keys[i]], end_frame[end_frame_keys[j]]):
                    #modified.append(end_frame[end_frame_keys[j]])
                    self._add_feature_to_list(end_frame, end_frame_keys[j], modified)
                i += 1
                j += 1
                
        frame_diff = {'added': added, 'deleted': deleted, 'modified': modified}
        search.logger.logger.debug('get_raw_namespace_diff: Diff = <<< %s >>>', json.dumps(frame_diff, indent=2)) 
        return frame_diff
    
    def get_namespace_diff_report(self, frame_diff):
        added = self._group_frame_diff_by_feature_type(frame_diff, 'added', filter=True)
        modified = self._group_frame_diff_by_feature_type(frame_diff, 'modified', filter=True)
        deleted = self._group_frame_diff_by_feature_type(frame_diff, 'deleted', filter=True)
        
        added_feature_tables = self._grouped_frame_diff_to_feature_tables(added)
        deleted_feature_tables = self._grouped_frame_diff_to_feature_tables(deleted)
        #modified_feature_tables = self._grouped_frame_diff_to_feature_tables(modified)
        
        #feature_tables_dict = {'added': added_feature_tables, 'deleted': deleted_feature_tables, 'modified': modified_feature_tables}
        feature_tables_dict = {'added': added_feature_tables, 'deleted': deleted_feature_tables}
        search.logger.logger.debug('get_namespace_diff_report: tables = <<< %s >>>', json.dumps(feature_tables_dict, indent=2))
        return feature_tables_dict
    
    def _group_frame_diff_by_feature_type(self, frame_diff, key, filter=False):
        grouped_dict = {}
        for feature in frame_diff[key]:
            #print "frame_diff[%s] = %s" % (key, frame_diff[key])
            #print "frame_diff[%s][0] = %s" % (key, frame_diff[key][0])
            #print frame_diff[key][0].__class__
            singleton_feature_value = feature.values()
            feature_type = singleton_feature_value[0]['feature_type']
            if filter and self._should_filter(feature_type, singleton_feature_value[0]):
                continue
            if feature_type not in grouped_dict:
                grouped_dict[feature_type] = []
            grouped_dict[feature_type].append(singleton_feature_value[0])
        return grouped_dict
    
    def _should_filter(self, feature_type, feature_value):
        if feature_type == 'file':
            for to_be_filtered in ConfigDataHandler.FILTERED_FILE_PATHS:
                if to_be_filtered in feature_value['path']:
                    return True
        return False
    
    def _grouped_frame_diff_to_feature_tables(self, grouped_frame_diff):
        tables = {}
        for ft in sorted(grouped_frame_diff.keys()):
            table = prettytable.PrettyTable(feature_tables.get_feature_table_column_headers(ft))
            for feature in grouped_frame_diff[ft]:
                table.add_row(feature_tables.get_feature_table_row(ft, feature))
            tables[ft] = table.get_html_string(attributes=feature_tables.html_table_attributes)
        return tables
    
    def _add_feature_to_ui_list(self, frame, key, list):
        feature = frame[key]
        del feature['contents_hash']
        #del feature['key_hash']
        list.append(feature)
    
    def _add_feature_to_list(self, frame, key, list):
        list.append({key : frame[key]})
    
    def _is_modified(self, feature1, feature2):
        return feature1['contents_hash'] != feature2['contents_hash'] 
    
    def _get_query_to_assemble_frame(self, timestamp, namespace, features):
        fields_of_interest = [x + ".*" for x in features]
        fields_of_interest.extend(ConfigDataHandler.FEATURE_ID_FIELDS)
        query_body = '''
{
  "_source": %s,
  "query": {
     "filtered": {
        "filter": {
          "bool": {
            "must": [
              { "term": { "timestamp" : "%s" }},
              { "term": { "namespace.raw" : "%s" }},
              { "terms": { "feature_type.raw" : %s}}
            ]
          }
        }
      }
   }
}
''' % (fields_of_interest, timestamp, namespace, features)
        return query_body.replace("'", '"')
    
    def _get_closest_crawl_timestamp(self, namespace, timestamp, time_span_in_days):
        query_body_template = '''
{
  "_source": ["timestamp"],
  "query": {
     "filtered": {
        "filter": {
          "bool" : {
            "must": [
              {"term": { "namespace.raw" : "%s"}},
              {"term": { "feature_type.raw" : "os"}},
              {"range": { "timestamp": {"from":"%s", "to": "%s"}}}
            ]
          }
        }
      }
   },
   "sort": [{"timestamp": "%s"}]
}
'''
        # Perform a query for the time interval [(t - days), t]
        time_minus_delta = search.util.datetime_util.get_iso_timestamp_plus_delta_days(timestamp, -time_span_in_days)
        query_closest_earlier = query_body_template % (namespace, time_minus_delta, timestamp, 'desc')
        targeted_indices = search.util.datetime_util.get_indices_list_from_iso_timestamp_dayspan(timestamp, -time_span_in_days, ConfigDataHandler.CONFIG_INDEX_PREFIX)
        existing_indices = self._get_existing_indices(targeted_indices)
        index = ','.join(existing_indices)
        search.logger.logger.debug('_get_closest_crawl_timestamp: Querying interval [(t - %s), t]; Indices: %s' % (time_span_in_days, index))
        search.logger.logger.debug('_get_closest_crawl_timestamp: Query: %s' % query_closest_earlier)
        result_earlier = self.es_client.search(index=index, doc_type=ConfigDataHandler.CONFIG_DOC_TYPE, body=query_closest_earlier, size=1, request_timeout=ConfigDataHandler.ELASTICSEARCH_REQUEST_TIMEOUT)
        
        # Perform a query for the time interval [t, (t + days)]
        time_plus_delta = search.util.datetime_util.get_iso_timestamp_plus_delta_days(timestamp, time_span_in_days)
        query_closest_later = query_body_template % (namespace, timestamp, time_plus_delta, 'asc')
        targeted_indices = search.util.datetime_util.get_indices_list_from_iso_timestamp_dayspan(timestamp, time_span_in_days, ConfigDataHandler.CONFIG_INDEX_PREFIX)
        existing_indices = self._get_existing_indices(targeted_indices)
        index = ','.join(existing_indices)
        search.logger.logger.debug('_get_closest_crawl_timestamp: Querying interval [(t - %s), t]; Indices: %s' % (time_span_in_days, index))
        search.logger.logger.debug('_get_closest_crawl_timestamp: Query: %s' % query_closest_later)
        result_later = self.es_client.search(index=index, doc_type=ConfigDataHandler.CONFIG_DOC_TYPE, body=query_closest_later, size=1, request_timeout=ConfigDataHandler.ELASTICSEARCH_REQUEST_TIMEOUT)

        # Determine which crawl timestamp is the closest to the given timestamp
        time_before = None
        time_after = None
        if len(result_earlier['hits']['hits']) > 0:
            time_before = result_earlier['hits']['hits'][0]['_source']['timestamp']
            search.logger.logger.debug('_get_closest_crawl_timestamp: Query time = %d ms -- Data for time before << %s >>' %
                (result_earlier['took'], result_earlier['hits']['hits'][0]))
        if len(result_later['hits']['hits']) > 0:
            time_after = result_later['hits']['hits'][0]['_source']['timestamp']
            search.logger.logger.debug('_get_closest_crawl_timestamp: Query time = %d ms -- Data for time after << %s >>' %
                (result_later['took'], result_later['hits']['hits'][0]))
            
        closest_time = None
        if time_before == None and time_after == None:
            search.logger.logger.info('_get_closest_crawl_timestamp: Could not find data for namespace %s, timestamp %s, and %s days before and after'
                % (namespace, timestamp, time_span_in_days))
            return None
        elif time_before == None:
            closest_time = time_after
        elif time_after == None:
            closest_time = time_before
        else:
            t_minus_before = search.util.datetime_util.compare_iso_timestamps(timestamp, time_before)
            after_minus_t = search.util.datetime_util.compare_iso_timestamps(time_after, timestamp)
            closest_time = time_before if t_minus_before <= after_minus_t else time_after
        
        search.logger.logger.debug('_get_closest_crawl_timestamp: Closest time = %s' % closest_time)
        return closest_time
        
    def _get_existing_indices(self, targeted_indices):
        existing_indices = []
        for i in targeted_indices:
            if self.indices_client.exists(i):
                existing_indices.append(i)
        return existing_indices
    
    def _get_indices(self, begin_time, end_time):
        targeted_indices = search.util.datetime_util.get_indices_list_from_iso_timestamps(begin_time, end_time, ConfigDataHandler.CONFIG_INDEX_PREFIX)
        existing_indices = []
        for i in targeted_indices:
            if self.indices_client.exists(i):
                existing_indices.append(i)
        return existing_indices
    
    def _index_iterator(self):
        '''
        Starting with the current date (in UTC), go backwards in time until the latest index is found.
        Stop trying if no index is found in the past 10 years.
        '''
        utc_dt = datetime.datetime.utcnow()
        current_day = 1
        while current_day <= 3650:
            index = search.util.datetime_util.get_index_from_date(utc_dt.date(), ConfigDataHandler.CONFIG_INDEX_PREFIX)
            if self.indices_client.exists(index):
                yield index
            utc_dt = utc_dt - datetime.timedelta(days=1)
            current_day += 1
    
    def _get_query_to_assemble_frames_list(self, begin_time, end_time, namespace, features):
        fields_of_interest = [x + ".*" for x in features]
        fields_of_interest.extend(ConfigDataHandler.FEATURE_ID_FIELDS)
        fields_of_interest.append('timestamp')
        query_body = '''
{
  "_source": %s,
  "query": {
     "filtered": {
        "filter": {
          "bool": {
            "must": [
              {"range": { "timestamp": {"from":"%s", "to": "%s"}}},
              { "term": { "namespace.raw" : "%s"}},
              { "terms": { "feature_type.raw" : %s}}
            ]
          }
        }
      }
   }
}
''' % (fields_of_interest, begin_time, end_time, namespace, features)
        return query_body.replace("'", '"')
