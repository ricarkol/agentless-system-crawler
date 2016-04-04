from flask import render_template
import traceback
import json
import elasticsearch
import search.cli.config
import search.logger
import search.data.configdata_handler
import search.util.datetime_util

import os.path

SERVICE_NAME = 'ELK-Cloudsight Search Service'
APPLICATION_JSON = 'application/json'
TEXT_PLAIN = 'text/plain'

class RestEndpointHandler:
    '''
    This class encapsulates the functions that handle REST requests made to the search service.
    '''

    def __init__(self, config=None):
        self.service_label = SERVICE_NAME
        
        self.es_cluster = config.get_elasticsearch_cluster() if config else search.cli.config.Config.DEFAULT_ES_CLUSTER
        self.es_client = elasticsearch.Elasticsearch(hosts=self.es_cluster)
        self.configdata_handler = search.data.configdata_handler.ConfigDataHandler(self.es_client)
        
        search.logger.logger.info('Target Elasticsearch: %s' % self.es_cluster)
        # Check if we can "ping" the Elasticsearch cluster
        if self.es_client.ping():
            search.logger.logger.info('Verified existing connectivity to the Elasticsearch cluster.')
        else:
            search.logger.logger.error('Failed to connect to one of more nodes of the Elasticsearch cluster.')
    
    def get_welcome(self):
        welcome_str = 'CloudSight Elasticsearch search service'
        return (welcome_str, 200, self._get_headers(welcome_str, TEXT_PLAIN))
    
    def diff_report_app(self):
        features = search.data.configdata_handler.ConfigDataHandler.ALL_FEATURES
        namespaces = self.configdata_handler.get_namespaces()
        return render_template('diff_digest.html', namespaces=namespaces, features=features)
    
    def namespace_diff_report_app(self):
        # XXX BEGIN HACK (due to lack of crawler's support for symbolic container namespaces)
        if os.path.isfile('/tmp/namespace-mapping.txt'):
            namespaces = []
            f = open('/tmp/namespace-mapping.txt', 'r')
            for line in f:
                namespaces.append(line.split(",")[0])
            f.close()
            # XXX END HACK (due to lack of crawler's support for symbolic container namespaces)
        else:
            namespaces = self.configdata_handler.get_namespaces()
            
        features = search.data.configdata_handler.ConfigDataHandler.ALL_FEATURES
        return render_template('namespace_diff_digest.html', namespaces=namespaces, features=features)
    
    @DeprecationWarning
    def index_document(self, request):
        try:
            args = request.args
            json_document = request.get_json(force=True)
            ok_or_args_error = self._validate_required_args(args, ['index', 'type'])
            if ok_or_args_error != True:
                return ok_or_args_error
        
            index = args.get('index')
            doc_type = args.get('type')
            doc_id = args.get('id', default=None, type=str)
            
            search.logger.logger.debug('index_document: index = "%s"; document = %s' % (index, json_document))
            result = self.es_client.index(index=index, doc_type=doc_type, id=doc_id, body=json_document)
            search.logger.logger.debug('index_document: result = %s' % result)
            response = json.dumps(result, indent=2)
            return (response, 201, self._get_headers(response))
        except Exception as e:
            msg = 'Error indexing document'
            return self._error_handler_response(exception=e, message=msg)
    
    @DeprecationWarning
    def retrieve_document(self, index, doctype, docid):
        try:
            search.logger.logger.debug('retrieve_document: index = %s; doctype = %s; docid = %s' % (index, doctype, docid))
            result = self.es_client.get(index, docid, doctype)
            search.logger.logger.debug('retrieve_document: result = %s' % result)
            response = json.dumps(result, indent=2)
            return (response, 200, self._get_headers(response))
        except Exception as e:
            msg = 'Error retrieving document'
            return self._error_handler_response(exception=e, message=msg)

    def get_namespaces(self, args):
        try:   
            begin_time = args.get('begin_time', default=None, type=str)
            end_time = args.get('end_time', default=None, type=str)
            if bool(begin_time) != bool(end_time):
                error_message = 'Both arguments "begin_time" and "end_time" must be given or omitted. One cannot appear without the other.'
                return self._error_handler_response(400, message=error_message)
            
            if bool(begin_time) and bool(end_time):
                begin_time = search.util.datetime_util.validate_and_convert_timestamp(begin_time) 
                if not begin_time:
                    error_message = 'Invalid time format for begin_time. Make sure the time is given in the ISO8601 format'
                    return self._error_handler_response(400, message=error_message)
                end_time = search.util.datetime_util.validate_and_convert_timestamp(end_time) 
                if not end_time:
                    error_message = 'Invalid time format for end_time. Make sure the time is given in the ISO8601 format'
                    return self._error_handler_response(400, message=error_message)
                if not search.util.datetime_util.is_valid_time_interval(begin_time, end_time):
                    error_message = 'Invalid time interval. End_time refers to a time before begin_time.'
                    return self._error_handler_response(400, message=error_message)
            
            namespaces = self.configdata_handler.get_namespaces(begin_time, end_time)
            status_code = 200
            if not namespaces:
                status_code = 404
            response = json.dumps({"namespaces": namespaces}, indent=2)
            return (response, status_code, self._get_headers(response))
        except Exception as e:
            msg = 'Error getting namespaces'
            return self._error_handler_response(exception=e, message=msg)
        
    def get_config_frame(self, args):
        try:
            ok_or_args_error = self._validate_required_args(args, ['timestamp', 'namespace'])
            if ok_or_args_error != True:
                return ok_or_args_error
            features_list = self._get_features_list(args.get('features', default=None, type=str))
            
            status_code = 200
            timestamp = args.get('timestamp')
            
            if timestamp.lower() == 'latest':
                # Need to get the latest frame
                frame = self.configdata_handler.get_latest_frame(args.get('namespace'), features_list)
            else:
                timestamp = search.util.datetime_util.validate_and_convert_timestamp(timestamp)
                if not timestamp:
                    error_message = 'Invalid time format for timestamp. Make sure the time is given in the ISO8601 format or is the string "latest".'
                    return self._error_handler_response(400, message=error_message)
                search_types = ['closest', 'exact']
                search_type = args.get('search_type')
                if not search_type:
                    search_type = 'closest'
                else:
                    search_type = search_type.lower()
                    if search_type not in search_types:
                        error_message = 'Invalid search_type value. Valid values are: %s' % search_types
                        return self._error_handler_response(400, message=error_message)
                time_span = args.get('time_span')
                if not time_span:
                    time_span = 0.25
                else:
                    try:
                        time_span = float(time_span)
                    except ValueError:
                        error_message = 'Invalid value for time_span. It must be a floating-point number.'
                        return self._error_handler_response(400, message=error_message)
                
                frame = self.configdata_handler.get_frame(timestamp, args.get('namespace'), features_list, search_type=search_type, time_span_in_days=time_span)
            
            response = json.dumps(frame, indent=2)
            if not frame:
                # No frame has been found
                status_code = 404
            return (response, status_code, self._get_headers(response))
            
        except Exception as e:
            msg = 'Error getting config frame'
            return self._error_handler_response(exception=e, message=msg)
    
    def get_config_frames(self, args):
        try:
            ok_or_args_error = self._validate_required_args(args, ['begin_time', 'end_time', 'namespace'])
            if ok_or_args_error != True:
                return ok_or_args_error
            begin_time = search.util.datetime_util.validate_and_convert_timestamp(args.get('begin_time')) 
            if not begin_time:
                error_message = 'Invalid time format for begin_time. Make sure the time is given in the ISO8601 format'
                return self._error_handler_response(400, message=error_message)
            end_time = search.util.datetime_util.validate_and_convert_timestamp(args.get('end_time')) 
            if not end_time:
                error_message = 'Invalid time format for end_time. Make sure the time is given in the ISO8601 format'
                return self._error_handler_response(400, message=error_message)
            if not search.util.datetime_util.is_valid_time_interval(begin_time, end_time):
                error_message = 'Invalid time interval. End_time refers to a time before begin_time.'
                return self._error_handler_response(400, message=error_message)
            
            features_list = self._get_features_list(args.get('features', default=None, type=str))
            frames = self.configdata_handler.get_frames(begin_time, end_time, args.get('namespace'), features_list)
            status_code = 200
            response = json.dumps({"frames": frames}, indent=2, sort_keys=True)
            if not frames:
                # No frame has been found
                status_code = 404
            return (response, status_code, self._get_headers(response))
            
        except Exception as e:
            msg = 'Error getting config frames'
            return self._error_handler_response(exception=e, message=msg)
        
    def get_config_frame_diff(self, args):
        try:
            ok_or_args_error = self._validate_required_args(args, ['begin_time', 'end_time', 'namespace'])
            if ok_or_args_error != True:
                return ok_or_args_error
            features_list = self._get_features_list(args.get('features', default=None, type=str))
            
            begin_time = search.util.datetime_util.validate_and_convert_timestamp(args.get('begin_time')) 
            if not begin_time:
                error_message = 'Invalid time format for begin_time. Make sure the time is given in the ISO8601 format'
                return self._error_handler_response(400, message=error_message)
            end_time = search.util.datetime_util.validate_and_convert_timestamp(args.get('end_time')) 
            if not end_time:
                error_message = 'Invalid time format for end_time. Make sure the time is given in the ISO8601 format'
                return self._error_handler_response(400, message=error_message)
            if not search.util.datetime_util.is_valid_time_interval(begin_time, end_time):
                    error_message = 'Invalid time interval. End_time refers to a time before begin_time.'
                    return self._error_handler_response(400, message=error_message)

            frame_diff = self.configdata_handler.get_raw_frame_diff(begin_time, end_time, args.get('namespace'), features_list)
            response = json.dumps(frame_diff, indent=2, sort_keys=True)
            return (response, 200, self._get_headers(response))
            
        except Exception as e:
            msg = 'Error getting config frame diff'
            return self._error_handler_response(exception=e, message=msg)
        

    def get_config_frame_diff_for_ui(self, args):
        try:
            ok_or_args_error = self._validate_required_args(args, ['begin_time', 'end_time', 'namespace'])
            if ok_or_args_error != True:
                return ok_or_args_error
            features_list = self._get_features_list(args.get('features', default=None, type=str))
            
            begin_time = search.util.datetime_util.validate_and_convert_timestamp(args.get('begin_time')) 
            if not begin_time:
                error_message = 'Invalid time format for begin_time. Make sure the time is given in the ISO8601 format'
                return self._error_handler_response(400, message=error_message)
            end_time = search.util.datetime_util.validate_and_convert_timestamp(args.get('end_time')) 
            if not end_time:
                error_message = 'Invalid time format for end_time. Make sure the time is given in the ISO8601 format'
                return self._error_handler_response(400, message=error_message)
            if not search.util.datetime_util.is_valid_time_interval(begin_time, end_time):
                    error_message = 'Invalid time interval. End_time refers to a time before begin_time.'
                    return self._error_handler_response(400, message=error_message)

            frame_diff = self.configdata_handler.get_raw_frame_diff_for_ui(begin_time, end_time, args.get('namespace'), features_list)
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
    
    def get_namespace_crawl_times(self, args):
        try:
            ok_or_args_error = self._validate_required_args(args, ['begin_time', 'end_time', 'namespace'])
            if ok_or_args_error != True:
                return ok_or_args_error 
            
            begin_time = search.util.datetime_util.validate_and_convert_timestamp(args.get('begin_time')) 
            if not begin_time:
                error_message = 'Invalid time format for begin_time. Make sure the time is given in the ISO8601 format'
                return self._error_handler_response(400, message=error_message)
            end_time = search.util.datetime_util.validate_and_convert_timestamp(args.get('end_time')) 
            if not end_time:
                error_message = 'Invalid time format for end_time. Make sure the time is given in the ISO8601 format'
                return self._error_handler_response(400, message=error_message)
            if not search.util.datetime_util.is_valid_time_interval(begin_time, end_time):
                error_message = 'Invalid time interval. End_time refers to a time before begin_time.'
                return self._error_handler_response(400, message=error_message)
            
            status_code = 200
            crawl_times = self.configdata_handler.get_namespace_crawl_times(args.get('namespace'), begin_time, end_time)
            if len(crawl_times) == 0:
                status_code = 404
            response = json.dumps({"crawl_times": crawl_times}, indent=2)
            return (response, status_code, self._get_headers(response))
        
        except Exception as e:
            msg = 'Error getting namespace crawl times' 
            return self._error_handler_response(exception=e, message=msg)
        
    
    def get_namespace_diff(self, args):
        try:
            ok_or_args_error = self._validate_required_args(args, ['namespace1', 'time1', 'namespace2', 'time2'])
            if ok_or_args_error != True:
                return ok_or_args_error
            features_list = self._get_features_list(args.get('features', default=None, type=str))
            namespace_diff = self.configdata_handler.get_raw_namespace_diff(args.get('namespace1'), args.get('time1'), args.get('namespace2'), args.get('time2'), features_list)
            response = json.dumps(namespace_diff, indent=2, sort_keys=True)
            return (response, 200, self._get_headers(response))
            
        except Exception as e:
            msg = 'Error getting namespace diff' 
            return self._error_handler_response(exception=e, message=msg)
    
    def get_namespace_diff_report(self, args):
        try:
            ok_or_args_error = self._validate_required_args(args, ['namespace1', 'time1', 'namespace2', 'time2'])
            if ok_or_args_error != True:
                return ok_or_args_error
            # XXX BEGIN HACK (due to lack of crawler's support for symbolic container namespaces)
            if os.path.isfile('/tmp/namespace-mapping.txt'):
                n_mapping = {}
                f = open('/tmp/namespace-mapping.txt', 'r')
                for line in f:
                    l_arr = line.split(",")
                    n_mapping[l_arr[0]] = l_arr[1].replace("\n","") 
                f.close()
                namespace1 = n_mapping[args.get('namespace1')]
                namespace2 = n_mapping[args.get('namespace2')]
            namespace1 = args.get('namespace1')
            namespace2 = args.get('namespace2')
            # XXX END HACK (due to lack of crawler's support for symbolic container namespaces)
            
            features_list = self._get_features_list(args.get('features', default=None, type=str))
            #namespace_diff = self.configdata_handler.get_raw_namespace_diff(args.get('namespace1'), args.get('time1'), args.get('namespace2'), args.get('time2'), features_list)
            namespace_diff = self.configdata_handler.get_raw_namespace_diff(namespace1, args.get('time1'), namespace2, args.get('time2'), features_list)
            diff_report = self.configdata_handler.get_namespace_diff_report(namespace_diff)
            
            response = json.dumps(diff_report)
            return (response, 200, self._get_headers(response))
        
        except Exception as e:
            msg = 'Error getting namespace diff report' 
            return self._error_handler_response(exception=e, message=msg)
        
    def _validate_required_args(self, args, keys):
        for key in keys:
            arg = args.get(key, default=None, type=str)
            if not arg:
                return self._error_handler_response(400, message="Missing required parameter %s" % key)
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
            search.logger.logger.error(traceback.format_exc())
            resp["exception"] = exception.__class__.__name__
            if exception.message:
                resp["exceptionMessage"] = exception.message
            if hasattr(exception, 'status_code'):
                status = exception.status_code
            resp["stacktrace"] = traceback.format_exc()
        if message:
            resp["message"] = message
        if more_info:
            resp["moreInfo"] = more_info
        response = json.dumps(resp)
        headers = self._get_headers(response)        
        return (response, status, headers)
