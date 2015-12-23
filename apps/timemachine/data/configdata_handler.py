import json
import prettytable
import util.datetime
import feature_tables
import requests
import logging

logger = logging.getLogger("cloudsight.timemachine")
class ConfigDataHandler:
    '''
    This class manipulates config crawler data indexed on Elasticsearch
    '''
    
    
    CONFIG_FEATURES = ["file", "config", "process", "os", "disk", "connection", "package", "dockerps", "dockerinspect", "dockerhistory"]
    ALL_FEATURES = sorted(CONFIG_FEATURES + ["metric", "cpu", "memory", "load", "interface"])
    FEATURE_ID_FIELDS = ["feature_key", "feature_type", "key_hash", "contents_hash"]
    
    
    def __init__(self, search_url):
        '''
        Arguments:
          - 'search_url': search service url.
        '''
        self.url = search_url
    
    def get_namespaces(self, begin_time=None, end_time=None):
        try:
            url = '{}/namespaces'.format(self.url)
            logger.debug('get_namespaces: url=%s' % url)
            if begin_time and end_time:
                url = '{}?begin_time={}&end_time={}'.format(url,begin_time, end_time) 
            r = requests.get(url)
            if r.status_code != 200:
                raise Exception('get_namespaces: namespaces{}, status_code={}'.format(url, r.status_code))
            return json.loads(r.content)
        except Exception, e:
            logger.error(e)        
            raise
    
    def get_frame(self, timestamp, namespace, features=[]):
        '''
          Returns a logical frame (dictionary) encompassing all feature documents indexed as part of the same crawl.
        The timestamp provided by the user is used to determine the closest crawl time we know about. If no
        exact timestamp match exist, the crawl time immediately preceding the provided timestamp is used. 
          Arguments:
          - 'timestamp': String with an ISO8601 timestamp
          - 'namespace': String representing the namespace identifying the source of the crawled features
          - 'features': Optional array of strings indicating the features that should be part of the logical frame. If
          the array is empty (default value), all config features that are indexed will be included in the returned
          logical frame.
        '''
        try:
            url = '{}/config/frame?namespace={}&timestamp={}&features={}'.format(self.url, namespace, timestamp, ",".join(features))
            r = requests.get(url)
            if r.status_code != 200:
                raise Exception('get_frame: namespace={}, status_code={}'.format(namespace, r.status_code))
            return json.loads(r.content)
        except Exception, e:
            logger.error(e)        
            raise
    
    def get_raw_frame_diff(self, begin_time, end_time, namespace, features=[]):
        try:
            url = '{}/config/frame/diff?namespace={}&begin_time={}&end_time={}&features={}'.format(self.url, namespace, begin_time, end_time, ",".join(features))
            print url
            r = requests.get(url)
            if r.status_code != 200:
                raise Exception('get_raw_frame_diff: namespace={}, status_code={}'.format(namespace, r.status_code))
            return json.loads(r.content)
        except Exception, e:
            logger.error(e)        
            raise
    
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
        logger.debug('get_frame_diff_report: tables = <<< %s >>>', json.dumps(feature_tables_dict, indent=2)) 
        return feature_tables_dict
    
    def _group_frame_diff_by_feature_type(self, frame_diff, key):
        grouped_dict = {}
        for feature in frame_diff[key]:
            #print "frame_diff[%s] = %s" % (key, frame_diff[key])
            #print "frame_diff[%s][0] = %s" % (key, frame_diff[key][0])
            #print frame_diff[key][0].__class__
            singleton_feature_value = feature.values()
            feature_type = singleton_feature_value[0]['feature_type'] 
            if feature_type not in grouped_dict:
                grouped_dict[feature_type] = []
            grouped_dict[feature_type].append(singleton_feature_value[0])
        return grouped_dict
    
    def _grouped_frame_diff_to_feature_tables(self, grouped_frame_diff):
        tables = {}
        for ft in sorted(grouped_frame_diff.keys()):
            table = prettytable.PrettyTable(feature_tables.get_feature_table_column_headers(ft))
            for feature in grouped_frame_diff[ft]:
                table.add_row(feature_tables.get_feature_table_row(ft, feature))
            tables[ft] = table.get_html_string(attributes=feature_tables.html_table_attributes)
        return tables
    
    def _add_feature_to_list(self, frame, key, list):
        list.append({key : frame[key]})
    
    def _is_modified(self, feature1, feature2):
        return feature1['contents_hash'] != feature2['contents_hash'] 
    
if __name__ == '__main__':
    search_host = 'http://demo3.sl.cloud9.ibm.com:8885'
    cs = ConfigDataHandler(search_host)
    #print cs.get_namespaces()
    #print cs.get_frame(namespace='redblackdemo/b674053bcd65', timestamp='2015-01-26T:09:00-0400', features=['process'])
    print json.dumps(cs.get_frame(namespace='redblackdemo/b674053bcd65', timestamp='2015-02-12T15:00-0400', features=['process']),indent=2)
    #print json.dumps(cs.get_raw_frame_diff(namespace='redblackdemo/b674053bcd65', begin_time='2015-02-12T14:00-0400', end_time='2015-02-12T20:00-0400', features=['process']),indent=2)

