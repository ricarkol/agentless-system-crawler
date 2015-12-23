from flask import render_template
import traceback
import json
import prettytable
import data.configdata_handler
import data.bookmarkdata_handler
import logging

APPLICATION_JSON = 'application/json'
TEXT_PLAIN = 'text/plain'

welcome_message = '''
Cloudsight Time Machine Application

HTTP API
------------------

GET /v0/bookmarks?[tags=comma separated tags] [namespaces=comma separated namespaces] [begin_time=utc datetime] [end_time=uts datetime]
   - Returns a list of all bookmarks in json form
   - optional parameter tags specifies a comma separated list of tags, bookmark is included if any tag appears
   - optional parameter namespaces specifies a comma separated list of namespaces, bookmark is included if any namespace appears
   - optional parameter begin_time specifies the beginning time of the interval
   - optional parameter end_time specifies the end time of the interval

POST /v0/bookmark
   - data consists of a json object:
     { "tags": [ list of tags ] -- cannot be empty
       "namespaces": [ list of namespaces ] -- can be empty
       "timestamp" : string in UTC format with timezone info
     }
   - Returns the id of the bookmark created

DELETE /v0/bookmark/<doc_id>
    - Deletes the bookmark with specified id

GET /v0/config/frame?timestamp=utc timestamp&namepace=NAMESPACE&[features=comma seperated list of feature types]
    - Returns a dictionary encompassing all features indexed close to specified timestamp.
      The timestamp provided by the user is used to determine the closest index. If no features are indexed
      at exactly specified time, then features from index operation immediately preceding the provided timestamp are returned
    - Arguments:
      - 'timestamp': String with an ISO8601 timestamp
      - 'namespace': String representing the namespace identifying the source of the crawled features
      - 'features': Optional comma separated strings indicating the features that should be part of the logical frame. 
         If no features are specified, then all config features that are indexed will be included in the results.

GET /v0/bookmark/diff?bokmark_1=doc_id&bookmark_2=doc_id&[features=comma separated list of feature types]&[namespace=comma separated namespaces]
    - Returns a dictionary consisting of differences between features from namespaces in bookmark 1 at corresponding times

GET /v0/config/frame/diff?namespace=NAMESPACE&begin_time=utc timestamp&end_time=utc timestamp&[features=comma separated list of feature types]
    - Returns a dictionary consisting of differences between features from a given namespace at two different times

GET /v0/namespaces?[begin_time= utc timestamp]&[end_time = utc timestamp]
   - Returns the list of available namespaces
   - optional parameter begin_time specifies the beginning time of the interval
   - optional parameter end_time specifies the end time of the interval

GET /welcome
   - Prints this  message 
   
GET /
   - Prints this  message 
   
HTTP Return Codes
-----------------

All APIs return one of the following HTTP return codes

Return-code   Possible reasons associated with this return-code

    200       (API was successfully executed, may return data depending on API specification)
    400       Unknown type, Missing required argument, Missing data
    404       Invalid API request
    405       API method not allowed, Invalid type
    500       Internal error (includes exception stack trace in DEBUG mode)

'''

logger = logging.getLogger("cloudsight.timemachine")
class RestEndpointHandler:
    '''
    This class encapsulates the functions that handle REST requests made to the search service.
    '''

    def __init__(self, args):
        self.service_label = 'Cloudsight Timemachine Application'
        self.service_port = args.port
        self.search_service = args.search_service if args.search_service.startswith('http://') else 'http://%s' % args.search_service
        self.elastic_cluster = args.elastic_search_cluster
        self.configdata_handler = data.configdata_handler.ConfigDataHandler(self.search_service)
        self.bookmarkdata_handler = data.bookmarkdata_handler.BookmarkDataHandler(self.elastic_cluster)
        logger.info('%s: %s' % (self.service_label, self.service_port))
        logger.info('SearchService: %s' % self.search_service)
        logger.info('Elastic Cluster: %s' % self.elastic_cluster)

    def get_welcome(self):
        return (welcome_message, 200, self._get_headers(welcome_message, TEXT_PLAIN))
    
    def timemachine_app(self):
        return render_template('index.html')

    def get_bookmarks(self, args):
        try:
            tags = args.get('tags', default=None, type=str)
            namespaces = args.get('namespaces', default=None, type=str)
            begin_time = args.get('begin_time', default=None, type=str)
            end_time = args.get('end_time', default=None, type=str)
            
            bookmarks = self.bookmarkdata_handler.get_bookmarks(tags, namespaces, begin_time, end_time)
            response = json.dumps(bookmarks, indent=2)
            return (response, 200, self._get_headers(response))
        except Exception as e:
            msg = 'Error getting bookmarks'
            return self._error_handler_response(exception=e, message=msg)

    def create_bookmark(self, request):
        try:
            args = request.args
            json_document = request.get_json(force=True)
            ok_or_args_error = self._validate_bookmark(json_document)
            if ok_or_args_error != True:
                return ok_or_args_error
        
            doc_id = args.get('id', default=None, type=str)
            logger.debug('create_bookmark:  %s' % (json_document))
            result = self.bookmarkdata_handler.create_bookmark(doc_id=doc_id, bookmark=json_document)
            logger.debug('create_bookmark: result = %s' % result)
            response = json.dumps(result, indent=2)
            return (response, 201, self._get_headers(response))
        except Exception as e:
            msg = 'Error creating bookmark'
            return self._error_handler_response(exception=e, message=msg)

    def diff_bookmark(self, request):
        try:
            args = request.args
            begin_time = args.get('begin_time', default=None, type=str)
            end_time = args.get('end_time', default=None, type=str)
            namespace = args.get('namespace', default=None, type=str)
            features_list = args.get('features', default=None, type=str)
            if begin_time is None or end_time is None or namespace is None:
                return self._error_handler_response(400, message="begin_time, end_time, and namespace are required parameters")
        
            features = []
            if features_list:
               features = features_list.split(',') 

            logger.debug('diff_bookmark:  begin_time={}, end_time={}, namespace={}, features_list={}'.format(begin_time, end_time, namespace, features))
            frame_diff = self.configdata_handler.get_raw_frame_diff(begin_time, end_time, namespace, features)
            response = json.dumps(frame_diff, indent=2, sort_keys=True)
            return (response, 200, self._get_headers(response))
        except Exception as e:
            msg = 'Error computing diff'
            return self._error_handler_response(exception=e, message=msg)


    def delete_bookmark(self, doc_id):
        try:
            result = self.bookmarkdata_handler.delete_bookmark(doc_id=doc_id)
            return ('ok', 200, self._get_headers('ok', content_type=TEXT_PLAIN))
        except Exception as e:
            msg = 'Error deleting bookmark'
            return self._error_handler_response(exception=e, message=msg)
           
    
    def diff_report_app(self):
        features = search.data.configdata_handler.ConfigDataHandler.ALL_FEATURES
        namespaces = self.configdata_handler.diff_report_app()
        return render_template('diff_digest.html', namespaces=namespaces, features=features)
    
    def get_namespaces(self, args):
        try:
            logger.debug('get_namespaces: ')
            begin_time = args.get('begin_time', default=None, type=str)
            end_time = args.get('end_time', default=None, type=str)
            if bool(begin_time) != bool(end_time):
                error_message = 'Both arguments "begin_time" and "end_time" must be given or omitted. One cannot appear without the other.'
                return self._error_handler_response(400, message=error_message)
            
            namespaces = self.configdata_handler.get_namespaces(begin_time, end_time)
            response = json.dumps({"namespaces": namespaces}, indent=2)
            return (response, 200, self._get_headers(response))
        except Exception as e:
            msg = 'Error getting namespaces'
            return self._error_handler_response(exception=e, message=msg)
        
    def get_config_frame(self, args):
        try:
            ok_or_args_error = self._validate_required_args(args, ['timestamp', 'namespace'])
            if ok_or_args_error != True:
                return ok_or_args_error
            features_list = self._get_features_list(args.get('features', default=None, type=str))
            
            frame = self.configdata_handler.get_frame(args.get('timestamp'), args.get('namespace'), features_list)
            response = json.dumps(frame, indent=2)
            return (response, 200, self._get_headers(response))
            
        except Exception as e:
            msg = 'Error getting config frame'
            return self._error_handler_response(exception=e, message=msg)
        
    def get_config_frame_diff(self, args):
        try:
            ok_or_args_error = self._validate_required_args(args, ['begin_time', 'end_time', 'namespace'])
            if ok_or_args_error != True:
                return ok_or_args_error
            features_list = self._get_features_list(args.get('features', default=None, type=str))
            frame_diff = self.configdata_handler.get_raw_frame_diff(args.get('begin_time'), args.get('end_time'), args.get('namespace'), features_list)
            response = json.dumps(frame_diff, indent=2, sort_keys=True)
            return (response, 200, self._get_headers(response))
        except Exception as e:
            msg = 'Error getting config frame diff'
            return self._error_handler_response(exception=e, message=msg)
        
    def get_config_frame_diff_report(self, args):
        try:
            ok_or_args_error = self._validate_required_args(args, ['begin_time', 'end_time', 'namespace'])
            if ok_or_args_error != True:
                return ok_or_args_error
            features_list = self._get_features_list(args.get('features', default=None, type=str))
            frame_diff = self.configdata_handler.get_raw_frame_diff(args.get('begin_time'), args.get('end_time'), args.get('namespace'), features_list)
            diff_report = self.configdata_handler.get_frame_diff_report(frame_diff) 
            
            response = json.dumps(diff_report)
            return (response, 200, self._get_headers(response))
        
        except Exception as e:
            msg = 'Error getting config frame diff report' 
            return self._error_handler_response(exception=e, message=msg)        
        
    def _validate_required_args(self, args, keys):
        for key in keys:
            arg = args.get(key, default=None, type=str)
            if not arg:
                return self._error_handler_response(400, message="Missing required parameter %s" % key)
        return True
    
    def _validate_bookmark(self, bookmark):
       
        if not "tags" in bookmark: 
            return self._error_handler_response(400, message="Missing 'tags' ")
            #if isinstance(bookmark["tags"], list):
            #    if not bookmark["tags"]:
            #        return self._error_handler_response(400, message="Empty list of tags")
            #else:
            #    return self._error_handler_response(400, message="'tags' value should be a list")
       # else:
       #     return self._error_handler_response(400, message="Missing 'tags' ")

        if not "namespaces" in bookmark: 
            return self._error_handler_response(400, message="Missing 'namespaces' ")
            #if not isinstance(bookmark["namespaces"], list):
            #    return self._error_handler_response(400, message="'namespaces' value should be a list")
        #else:
        #    return self._error_handler_response(400, message="Missing 'namespaces' ")

        if not "timestamp" in bookmark: 
            return self._error_handler_response(400, message="Missing 'timestamp'")
            
        return True

    def _get_features_list(self, features_str_list):
        features_list = []
        if features_str_list:
            features_list = features_str_list.replace(' ', '').split(',')
        return features_list
    
    def _get_headers(self, response, content_type=APPLICATION_JSON):   
        headers = {'Server' : self.service_label, 'Content-Type' : content_type}
        if issubclass(type(response), basestring):
            headers['Content-Length'] = response.__len__()
        return headers
            
    def _error_handler_response(self, status=500, status_text=None, exception=None, message=None, more_info=None):
        resp = {}
        if (status_text):
            resp["statusText"] = status_text
        if exception:
            logger.error(traceback.format_exc())
            resp["exception"] = exception.__class__.__name__
            if exception.message:
                resp["exceptionMessage"] = exception.message
            if hasattr(exception, 'status_code'):
                status = exception.status_code
            #resp["stacktrace"] = traceback.format_exc()
        if message:
            resp["message"] = message
        if more_info:
            resp["moreInfo"] = more_info
        response = json.dumps(resp)
        headers = self._get_headers(response)        
        return (response, status, headers)
