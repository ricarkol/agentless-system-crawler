import unittest
import re
import json
import dateutil.parser
import search.cli.config
import search.endpoint.rest_endpoint

target_es_cluster = 'localhost:9222'
service_port = 5555

config = search.cli.config.Config()
config.set_port(service_port)
config.set_elasticsearch_cluster(target_es_cluster)
config.set_verbose(True)

search.endpoint.rest_endpoint.setup_app(config, True)
test_app = search.endpoint.rest_endpoint.app.test_client()

class RestEndpointTestCases(unittest.TestCase):
    def test_get_namespaces(self):
        begin_time = ['2015-02-21T10:00-05:00', '2015-02-21T15:00Z']
        end_time = ['2015-02-28T23:55-05:00', '2015-03-01T04:55-00:00']
        
        # Get namespaces given a time interval
        for i in range(2):
            resp = test_app.get('/namespaces?begin_time=%s&end_time=%s' % (begin_time[i], end_time[i]))
            
            self.assertIn('200', resp.status, "Status string should have '200'")
            self.assertEqual(resp.status_code, 200, "Status code does not equal 200 OK")
            self._assert_headers(resp)
            
            resp_dict = json.loads(resp.data)
            namespace_list = resp_dict['namespaces']
            # Namespace list size assertion
            self.assertEqual(len(namespace_list), 21, 'Unexpected size of namespace list')
            
            # Namespace list contents assertion
            expected_namespace_list = [
              "btak-server1",
              "btak-server10",
              "btak-server11",
              "btak-server12",
              "btak-server2",
              "btak-server3",
              "btak-server4",
              "btak-server5",
              "btak-server6",
              "btak-server7",
              "btak-server8",
              "btak-server9",
              "fabio-test-server",
              "priyacanarytest",
              "proteus-fabio-test",
              "proteus-fabio-test/434aa558ffa5",
              "proteus-fabio-test/4f53ab1cb899",
              "proteus-fabio-test/c514ae9eee39",
              "proteus-fabio-test/ef98f7bf8362",
              "regcrawl-image-2cea2911ebcb",
              "regcrawl-image-2cea2911ebcb/364468a114b0"
            ]
            self.assertEqual(sorted(namespace_list), sorted(expected_namespace_list), 'Unexpected namespace list')
            
        # TODO: Add a test for getting ALL namespaces (without specifying a time interval)
    
    def test_get_namespaces_errors(self):
        bad_begin_time = '2015-02-0315:00Z'
        begin_time = '2015-02-03T15:00Z'
        end_time = '2015-02-03T15:55-00:00'
        bad_end_time = '2015-02-03T15:5-00:00'
        
        # Bad begin time
        resp = test_app.get('/namespaces?begin_time=%s&end_time=%s' % (bad_begin_time, end_time))
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        self.assertIn('400', resp.status, "Status string should have '400'")
        self.assertEqual(resp.status_code, 400, "Status code does not equal 400")
        self.assertEqual(resp_dict['message'], 'Invalid time format for begin_time. Make sure the time is given in the ISO8601 format', 'Unexpected timestamp validation error message')
        
        # Bad end time
        resp = test_app.get('/namespaces?begin_time=%s&end_time=%s' % (begin_time, bad_end_time))
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        self.assertIn('400', resp.status, "Status string should have '400'")
        self.assertEqual(resp.status_code, 400, "Status code does not equal 400")
        self.assertEqual(resp_dict['message'], 'Invalid time format for end_time. Make sure the time is given in the ISO8601 format', 'Unexpected timestamp validation error message')
        
        # Incomplete interval (missing end time)
        resp = test_app.get('/namespaces?begin_time=%s' % (begin_time))
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        self.assertIn('400', resp.status, "Status string should have '400'")
        self.assertEqual(resp.status_code, 400, "Status code does not equal 400")
        self.assertEqual(resp_dict['message'], 'Both arguments "begin_time" and "end_time" must be given or omitted. One cannot appear without the other.', 'Unexpected timestamp validation error message')
        
        # Invalid interval (end time before begin time)
        resp = test_app.get('/namespaces?begin_time=%s&end_time=%s' % (end_time, begin_time))
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        self.assertIn('400', resp.status, "Status string should have '400'")
        self.assertEqual(resp.status_code, 400, "Status code does not equal 400")
        self.assertEqual(resp_dict['message'], 'Invalid time interval. End_time refers to a time before begin_time.', 'Unexpected timestamp validation error message')
        
    def test_get_frame(self):
        timestamp = '2015-02-28T10:00-05:00'
        timestamp2 = '2015-03-01T10:00-05:00'
        namespace = 'btak-server7'
        features = 'os'
        time_span = 2
               
        expected_os_feature_json = '''
{ 
  "linux": {
    "osrelease": "3.8.0-29-generic", 
    "osplatform": "i686", 
    "osdistro": "Ubuntu", 
    "feature_type": "os", 
    "key_hash": "50b7fdc858aa3576fd528eb51951fd705d9022e2", 
    "ipaddr": [
      "127.0.0.1", 
      "192.168.122.99"
    ], 
    "osname": "Linux-3.8.0-29-generic-i686-with-Ubuntu-12.04-precise", 
    "contents_hash": "419a8f9ebea6ef078a4708f3103647683796b29e", 
    "boottime": 1424357192.0, 
    "ostype": "linux", 
    "osversion": "#42~precise1-Ubuntu SMP Wed Aug 14 15:31:16 UTC 2013"
  }
}
'''
        expected_os_feature_dict = json.loads(expected_os_feature_json)
        
        # Successful closest match searches
        resp = test_app.get('/config/frame?timestamp=%s&namespace=%s&features=%s&time_span=%s' % (timestamp, namespace, features, time_span))
        self.assertIn('200', resp.status, "Status string should have '200'")
        self.assertEqual(resp.status_code, 200, "Status code does not equal 200 OK")
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        crawl_time = resp_dict['timestamp']
        dt_crawl = dateutil.parser.parse(crawl_time)
        expected_crawl_time = '2015-02-27T22:44:48-0500'
        dt_expected = dateutil.parser.parse(expected_crawl_time)
        self.assertEqual(dt_crawl, dt_expected, 'Unexpected crawl time of returned frame')
        self.assertEqual(cmp(expected_os_feature_dict['linux'], resp_dict['linux']), 0,  'Unexpected frame was returned')
        
        for t_span in [0.25, 1, 2]:
            resp = test_app.get('/config/frame?timestamp=%s&namespace=%s&features=%s&time_span=%s' % (timestamp2, namespace, features, t_span))
            self.assertIn('200', resp.status, "Status string should have '200'")
            self.assertEqual(resp.status_code, 200, "Status code does not equal 200 OK")
            self._assert_headers(resp)
            resp_dict = json.loads(resp.data)
            crawl_time = resp_dict['timestamp']
            dt_crawl = dateutil.parser.parse(crawl_time)
            expected_crawl_time = '2015-03-01T09:58:51-0500'
            dt_expected = dateutil.parser.parse(expected_crawl_time)
            self.assertEqual(dt_crawl, dt_expected, 'Unexpected crawl time of returned frame')
            self.assertEqual(cmp(expected_os_feature_dict['linux'], resp_dict['linux']), 0,  'Unexpected frame was returned')
        
        # Successfull exact match search
        timestamp3 = '2015-03-01T09:58:51-0500'
        resp = test_app.get('/config/frame?timestamp=%s&namespace=%s&features=%s&search_type=exact' % (timestamp3, namespace, features))
        self.assertIn('200', resp.status, "Status string should have '200'")
        self.assertEqual(resp.status_code, 200, "Status code does not equal 200 OK")
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        crawl_time = resp_dict['timestamp']
        dt_crawl = dateutil.parser.parse(crawl_time)
        expected_crawl_time = '2015-03-01T09:58:51-0500'
        dt_expected = dateutil.parser.parse(expected_crawl_time)
        self.assertEqual(dt_crawl, dt_expected, 'Unexpected crawl time of returned frame')
        self.assertEqual(cmp(expected_os_feature_dict['linux'], resp_dict['linux']), 0,  'Unexpected frame was returned')
        
        # Exact match search returns no results
        resp = test_app.get('/config/frame?timestamp=%s&namespace=%s&features=%s&search_type=exact' % (timestamp2, namespace, features))
        self.assertIn('404', resp.status, "Status string should have '404'")
        self.assertEqual(resp.status_code, 404, "Status code does not equal 404")
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        self.assertFalse(resp_dict, 'The search should have returned an empty frame')
        
        # Closest match search returns no results
        timestamp4 = '2015-03-01T05:00-05:00'
        time_span2 = 0.1
        resp = test_app.get('/config/frame?timestamp=%s&namespace=%s&features=%s&time_span=%s' % (timestamp4, namespace, features, time_span2))
        self.assertIn('404', resp.status, "Status string should have '404'")
        self.assertEqual(resp.status_code, 404, "Status code does not equal 404")
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        self.assertFalse(resp_dict, 'The search should have returned an empty frame')
    
    def test_get_frame_errors(self):
        timestamp = '2015-02-25T10:00-05:00'
        namespace = 'fabio-test-server'
        features = 'os'
        invalid_time_span = 'ttt'
        bad_time1 = '2015-02-0315:00Z'
        bad_time2 = '2015-02-03T15:5-00:00'
        invalid_search_type = 'close'
        
        # Bad time span
        resp = test_app.get('/config/frame?timestamp=%s&namespace=%s&features=%s&time_span=%s' % (timestamp, namespace, features, invalid_time_span))
        self._assert_headers(resp)
        self.assertIn('400', resp.status, "Status string should have '400'")
        self.assertEqual(resp.status_code, 400, "Status code does not equal 400")
        resp_dict = json.loads(resp.data)
        self.assertEqual(resp_dict['message'], 'Invalid value for time_span. It must be a floating-point number.', 'Unexpected time_span validation error message')
        
        # Bad timestamp
        resp = test_app.get('/config/frame?timestamp=%s&namespace=%s' % (bad_time1, namespace))
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        self.assertIn('400', resp.status, "Status string should have '400'")
        self.assertEqual(resp.status_code, 400, "Status code does not equal 400")
        self.assertEqual(resp_dict['message'], 'Invalid time format for timestamp. Make sure the time is given in the ISO8601 format or is the string "latest".', 'Unexpected timestamp validation error message')

        # Bad timestamp        
        resp = test_app.get('/config/frame?timestamp=%s&namespace=%s' % (bad_time2, namespace))
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        self.assertIn('400', resp.status, "Status string should have '400'")
        self.assertEqual(resp.status_code, 400, "Status code does not equal 400")
        self.assertEqual(resp_dict['message'], 'Invalid time format for timestamp. Make sure the time is given in the ISO8601 format or is the string "latest".', 'Unexpected timestamp validation error message')
        
        # Invalid search type
        resp = test_app.get('/config/frame?timestamp=%s&namespace=%s&search_type=%s' % (timestamp, namespace, invalid_search_type))
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        self.assertIn('400', resp.status, "Status string should have '400'")
        self.assertEqual(resp.status_code, 400, "Status code does not equal 400")
        self.assertRegexpMatches(resp_dict['message'], 'Invalid search_type value. Valid values are', 'Unexpected search_type validation error message')

    def test_get_latest_frame(self):
        namespace = 'btak-server7'
        features = 'os'
        expected_crawl_time = '2015-03-01T23:55:13+00:00'
        expected_os_feature_json = '''
{ 
  "linux": {
    "osrelease": "3.8.0-29-generic", 
    "osplatform": "i686", 
    "osdistro": "Ubuntu", 
    "feature_type": "os", 
    "key_hash": "50b7fdc858aa3576fd528eb51951fd705d9022e2", 
    "ipaddr": [
      "127.0.0.1", 
      "192.168.122.99"
    ], 
    "osname": "Linux-3.8.0-29-generic-i686-with-Ubuntu-12.04-precise", 
    "contents_hash": "419a8f9ebea6ef078a4708f3103647683796b29e", 
    "boottime": 1424357192.0, 
    "ostype": "linux", 
    "osversion": "#42~precise1-Ubuntu SMP Wed Aug 14 15:31:16 UTC 2013"
  }
}
'''
        expected_os_feature_dict = json.loads(expected_os_feature_json) 
        resp = test_app.get('/config/frame?timestamp=latest&namespace=%s&features=%s' % (namespace, features))
        self.assertIn('200', resp.status, "Status string should have '200'")
        self.assertEqual(resp.status_code, 200, "Status code does not equal 200 OK")
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        crawl_time = resp_dict['timestamp']
        dt_crawl = dateutil.parser.parse(crawl_time)
        dt_expected = dateutil.parser.parse(expected_crawl_time)
        self.assertEqual(dt_crawl, dt_expected, 'Unexpected crawl time of returned frame')
        self.assertEqual(cmp(expected_os_feature_dict['linux'], resp_dict['linux']), 0,  'Unexpected frame was returned')
        
        inexistent_namespace = 'not-there'
        resp = test_app.get('/config/frame?timestamp=latest&namespace=%s&features=%s' % (inexistent_namespace, features))
        self.assertIn('404', resp.status, "Status string should have '404'")
        self.assertEqual(resp.status_code, 404, "Status code does not equal 404")
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        self.assertFalse(resp_dict, 'The search should have returned an empty frame')
    
    def test_get_namespace_crawl_times(self):
        begin_time = '2015-03-01T10:00-05:00'
        end_time = '2015-03-01T11:00-05:00'
        namespace = 'btak-server7'
        expected_crawl_times = [
            "2015-03-01T15:55:02Z", 
            "2015-03-01T15:50:00Z", 
            "2015-03-01T15:44:59Z", 
            "2015-03-01T15:39:58Z", 
            "2015-03-01T15:34:35Z", 
            "2015-03-01T15:29:33Z", 
            "2015-03-01T15:24:30Z", 
            "2015-03-01T15:19:23Z", 
            "2015-03-01T15:14:06Z", 
            "2015-03-01T15:08:59Z",
            "2015-03-01T15:03:58Z"
        ]
        expected_crawl_dts = [ dateutil.parser.parse(x) for x in expected_crawl_times ]
        
        # Search returning results
        resp = test_app.get('/namespace/crawl_times?namespace=%s&begin_time=%s&end_time=%s' % (namespace, begin_time, end_time))
        self.assertIn('200', resp.status, "Status string should have '200'")
        self.assertEqual(resp.status_code, 200, "Status code does not equal 200 OK")
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        crawl_times_list = resp_dict['crawl_times']
        crawl_dts = [ dateutil.parser.parse(x) for x in crawl_times_list ]
        self.assertEqual(len(crawl_times_list), 11, 'Unexpected size of crawl times list')
        self.assertEqual(expected_crawl_dts, crawl_dts, 'Unexpected crawl times list')
        
        # Search returning no results
        namespace = 'not-there'
        resp = test_app.get('/namespace/crawl_times?namespace=%s&begin_time=%s&end_time=%s' % (namespace, begin_time, end_time))
        self.assertIn('404', resp.status, "Status string should have '404'")
        self.assertEqual(resp.status_code, 404, "Status code does not equal 404 OK")
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        crawl_times_list = resp_dict['crawl_times']
        self.assertEqual(len(crawl_times_list), 0, 'Unexpected size of crawl times list')
    
    def test_get_frames(self):
        namespace = 'btak-server7'
        begin_time = '2015-02-01T10:00-05:00'
        end_time = '2015-03-02T22:00-05:00'
        features='os'
        expected_crawl_times = [
      "2015-03-01T18:55:13-0500", 
      "2015-03-01T18:50:12-0500", 
      "2015-03-01T18:45:09-0500", 
      "2015-03-01T18:39:58-0500", 
      "2015-03-01T18:34:51-0500", 
      "2015-03-01T18:29:48-0500", 
      "2015-03-01T18:24:46-0500", 
      "2015-03-01T18:19:38-0500", 
      "2015-03-01T18:14:37-0500", 
      "2015-03-01T18:09:30-0500", 
      "2015-03-01T18:04:28-0500", 
      "2015-03-01T17:59:13-0500", 
      "2015-03-01T17:53:57-0500", 
      "2015-03-01T17:48:55-0500", 
      "2015-03-01T17:43:43-0500", 
      "2015-03-01T17:38:14-0500", 
      "2015-03-01T17:33:07-0500", 
      "2015-03-01T17:28:04-0500", 
      "2015-03-01T17:22:57-0500", 
      "2015-03-01T17:17:52-0500", 
      "2015-03-01T17:12:49-0500", 
      "2015-03-01T17:07:42-0500", 
      "2015-03-01T17:02:35-0500", 
      "2015-03-01T16:57:29-0500", 
      "2015-03-01T16:52:24-0500", 
      "2015-03-01T16:47:22-0500", 
      "2015-03-01T16:42:20-0500", 
      "2015-03-01T16:37:15-0500", 
      "2015-03-01T16:32:12-0500", 
      "2015-03-01T16:27:10-0500", 
      "2015-03-01T16:21:59-0500", 
      "2015-03-01T16:16:56-0500", 
      "2015-03-01T16:11:53-0500", 
      "2015-03-01T16:06:43-0500", 
      "2015-03-01T16:01:31-0500", 
      "2015-03-01T15:56:19-0500", 
      "2015-03-01T15:51:07-0500", 
      "2015-03-01T15:45:56-0500", 
      "2015-03-01T15:40:53-0500", 
      "2015-03-01T15:35:46-0500", 
      "2015-03-01T15:30:44-0500", 
      "2015-03-01T15:25:38-0500", 
      "2015-03-01T15:20:36-0500", 
      "2015-03-01T15:15:28-0500", 
      "2015-03-01T15:10:21-0500", 
      "2015-03-01T15:05:13-0500", 
      "2015-03-01T15:00:10-0500", 
      "2015-03-01T14:55:05-0500", 
      "2015-03-01T14:50:03-0500", 
      "2015-03-01T14:45:02-0500", 
      "2015-03-01T14:39:55-0500", 
      "2015-03-01T14:34:52-0500", 
      "2015-03-01T14:29:51-0500", 
      "2015-03-01T14:24:44-0500", 
      "2015-03-01T14:19:23-0500", 
      "2015-03-01T14:14:15-0500", 
      "2015-03-01T14:09:14-0500", 
      "2015-03-01T14:04:11-0500", 
      "2015-03-01T13:59:05-0500", 
      "2015-03-01T13:53:58-0500", 
      "2015-03-01T13:48:41-0500", 
      "2015-03-01T13:43:30-0500", 
      "2015-03-01T13:38:26-0500", 
      "2015-03-01T13:33:24-0500", 
      "2015-03-01T13:28:08-0500", 
      "2015-03-01T13:23:06-0500", 
      "2015-03-01T13:18:01-0500", 
      "2015-03-01T13:12:49-0500", 
      "2015-03-01T13:07:44-0500", 
      "2015-03-01T13:02:33-0500", 
      "2015-03-01T12:57:32-0500", 
      "2015-03-01T12:52:18-0500", 
      "2015-03-01T12:47:11-0500", 
      "2015-03-01T12:42:09-0500", 
      "2015-03-01T12:37:06-0500", 
      "2015-03-01T12:31:50-0500", 
      "2015-03-01T12:26:47-0500", 
      "2015-03-01T12:21:35-0500", 
      "2015-03-01T12:16:29-0500", 
      "2015-03-01T12:11:27-0500", 
      "2015-03-01T12:06:22-0500", 
      "2015-03-01T12:01:20-0500", 
      "2015-03-01T11:56:16-0500", 
      "2015-03-01T11:51:04-0500", 
      "2015-03-01T11:46:03-0500", 
      "2015-03-01T11:40:42-0500", 
      "2015-03-01T11:35:35-0500", 
      "2015-03-01T11:30:28-0500", 
      "2015-03-01T11:25:22-0500", 
      "2015-03-01T11:20:18-0500", 
      "2015-03-01T11:15:16-0500", 
      "2015-03-01T11:10:14-0500", 
      "2015-03-01T11:05:05-0500", 
      "2015-03-01T11:00:04-0500", 
      "2015-03-01T10:55:02-0500", 
      "2015-03-01T10:50:00-0500", 
      "2015-03-01T10:44:59-0500", 
      "2015-03-01T10:39:58-0500", 
      "2015-03-01T10:34:35-0500", 
      "2015-03-01T10:29:33-0500", 
      "2015-03-01T10:24:30-0500", 
      "2015-03-01T10:19:23-0500", 
      "2015-03-01T10:14:06-0500", 
      "2015-03-01T10:08:59-0500", 
      "2015-03-01T10:03:58-0500", 
      "2015-03-01T09:58:51-0500", 
      "2015-03-01T09:53:49-0500", 
      "2015-03-01T09:48:45-0500", 
      "2015-03-01T09:43:43-0500", 
      "2015-03-01T09:38:41-0500", 
      "2015-03-01T09:33:34-0500", 
      "2015-02-27T22:44:48-0500", 
      "2015-02-27T22:39:45-0500", 
      "2015-02-27T22:34:41-0500", 
      "2015-02-27T22:29:38-0500", 
      "2015-02-27T22:24:21-0500", 
      "2015-02-27T22:19:20-0500", 
      "2015-02-27T22:14:17-0500", 
      "2015-02-27T22:09:15-0500", 
      "2015-02-27T22:04:13-0500", 
      "2015-02-27T21:59:11-0500", 
      "2015-02-27T21:54:10-0500", 
      "2015-02-27T21:49:07-0500", 
      "2015-02-27T21:44:00-0500", 
      "2015-02-27T21:38:52-0500", 
      "2015-02-27T21:33:49-0500", 
      "2015-02-27T21:28:43-0500", 
      "2015-02-27T21:23:36-0500", 
      "2015-02-27T21:18:34-0500", 
      "2015-02-27T21:13:31-0500", 
      "2015-02-27T21:08:27-0500", 
      "2015-02-27T21:03:25-0500", 
      "2015-02-27T20:58:23-0500", 
      "2015-02-27T20:53:19-0500", 
      "2015-02-27T20:48:17-0500", 
      "2015-02-27T20:43:07-0500", 
      "2015-02-27T20:37:52-0500", 
      "2015-02-27T20:32:50-0500", 
      "2015-02-27T20:27:49-0500", 
      "2015-02-27T20:22:47-0500", 
      "2015-02-27T20:17:45-0500", 
      "2015-02-27T20:12:38-0500", 
      "2015-02-27T20:07:26-0500", 
      "2015-02-27T20:02:20-0500", 
      "2015-02-27T19:57:12-0500", 
      "2015-02-27T19:52:10-0500", 
      "2015-02-27T19:47:07-0500", 
      "2015-02-27T19:42:05-0500", 
      "2015-02-27T19:37:03-0500", 
      "2015-02-27T19:32:00-0500", 
      "2015-02-27T19:26:52-0500", 
      "2015-02-27T19:21:47-0500", 
      "2015-02-27T19:16:44-0500", 
      "2015-02-27T19:11:41-0500", 
      "2015-02-27T19:06:38-0500", 
      "2015-02-27T19:01:36-0500", 
      "2015-02-27T18:56:32-0500", 
      "2015-02-27T18:51:23-0500", 
      "2015-02-27T18:46:22-0500", 
      "2015-02-27T18:40:59-0500", 
      "2015-02-27T18:35:53-0500", 
      "2015-02-27T18:30:51-0500", 
      "2015-02-27T18:25:50-0500", 
      "2015-02-27T18:20:49-0500", 
      "2015-02-27T18:15:48-0500", 
      "2015-02-27T18:10:45-0500", 
      "2015-02-27T18:05:43-0500", 
      "2015-02-27T18:00:41-0500", 
      "2015-02-27T17:55:33-0500", 
      "2015-02-27T17:50:20-0500", 
      "2015-02-27T17:45:19-0500", 
      "2015-02-27T17:40:15-0500", 
      "2015-02-27T17:35:06-0500", 
      "2015-02-27T17:29:59-0500", 
      "2015-02-27T17:24:52-0500", 
      "2015-02-27T17:19:49-0500", 
      "2015-02-27T17:14:46-0500", 
      "2015-02-27T17:09:35-0500", 
      "2015-02-27T17:04:34-0500", 
      "2015-02-27T16:59:31-0500", 
      "2015-02-27T16:54:23-0500", 
      "2015-02-27T16:49:18-0500", 
      "2015-02-27T16:44:11-0500", 
      "2015-02-27T16:39:09-0500", 
      "2015-02-27T16:33:56-0500", 
      "2015-02-27T16:28:54-0500", 
      "2015-02-27T16:23:51-0500", 
      "2015-02-27T16:18:48-0500", 
      "2015-02-27T16:13:45-0500", 
      "2015-02-27T16:08:43-0500", 
      "2015-02-27T16:03:42-0500", 
      "2015-02-27T15:58:33-0500", 
      "2015-02-27T15:53:24-0500", 
      "2015-02-27T15:48:21-0500", 
      "2015-02-27T15:43:10-0500", 
      "2015-02-27T15:38:07-0500", 
      "2015-02-20T22:11:53-0500", 
      "2015-02-20T22:06:52-0500", 
      "2015-02-20T22:01:51-0500", 
      "2015-02-20T21:56:45-0500", 
      "2015-02-20T21:51:38-0500", 
      "2015-02-20T21:46:36-0500", 
      "2015-02-20T21:41:20-0500", 
      "2015-02-20T21:36:18-0500", 
      "2015-02-20T21:31:14-0500", 
      "2015-02-20T21:26:12-0500", 
      "2015-02-20T21:21:00-0500", 
      "2015-02-20T21:15:56-0500", 
      "2015-02-20T21:10:55-0500", 
      "2015-02-20T21:05:52-0500", 
      "2015-02-20T21:00:40-0500", 
      "2015-02-20T20:55:39-0500", 
      "2015-02-20T20:50:28-0500", 
      "2015-02-20T20:45:18-0500", 
      "2015-02-20T20:40:01-0500", 
      "2015-02-20T20:35:00-0500", 
      "2015-02-20T20:29:58-0500", 
      "2015-02-20T20:24:57-0500", 
      "2015-02-20T20:19:47-0500", 
      "2015-02-20T20:14:46-0500", 
      "2015-02-20T20:09:44-0500", 
      "2015-02-20T20:04:43-0500", 
      "2015-02-20T19:59:40-0500", 
      "2015-02-20T19:54:29-0500", 
      "2015-02-20T19:49:22-0500", 
      "2015-02-20T19:44:16-0500", 
      "2015-02-20T19:39:15-0500", 
      "2015-02-20T19:34:14-0500", 
      "2015-02-20T19:29:13-0500", 
      "2015-02-20T19:24:05-0500", 
      "2015-02-20T19:18:59-0500", 
      "2015-02-20T19:13:53-0500", 
      "2015-02-20T19:08:52-0500", 
      "2015-02-20T19:03:51-0500"
        ]
        
        # Search returning results
        resp = test_app.get('/config/frames?namespace=%s&begin_time=%s&end_time=%s&features=%s' % (namespace, begin_time, end_time, features))
        self.assertIn('200', resp.status, "Status string should have '200'")
        self.assertEqual(resp.status_code, 200, "Status code does not equal 200 OK")
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        crawl_times_list = resp_dict['frames']['timestamps']
        self.assertEqual(len(crawl_times_list), 234, 'Unexpected size of crawl times list')
        self.assertEqual(expected_crawl_times, crawl_times_list, 'Unexpected crawl times list')
        
        # Search returning no results
        namespace = 'not-there'
        resp = test_app.get('/config/frames?namespace=%s&begin_time=%s&end_time=%s&features=%s' % (namespace, begin_time, end_time, features))
        self.assertIn('404', resp.status, "Status string should have '404'")
        self.assertEqual(resp.status_code, 404, "Status code does not equal 404 OK")
        self._assert_headers(resp)
        resp_dict = json.loads(resp.data)
        self.assertDictEqual(resp_dict['frames'], {}, 'The returned dictionary must be empty.')
    
    def _assert_headers(self, resp):
        self.assertIn('Content-Length', resp.headers, "Missing 'Content-Length' in headers")
        self.assertIn('Content-Type', resp.headers, "Missing 'Content-Type' in headers")
        self.assertIn('Server', resp.headers, "Missing 'Server' in headers")
        self.assertEquals(resp.headers['Content-Type'], search.endpoint.rest_endpoint_handler.APPLICATION_JSON, "Content-Type in headers is not %s" % search.endpoint.rest_endpoint_handler.APPLICATION_JSON)
        self.assertTrue(re.search(search.endpoint.rest_endpoint_handler.SERVICE_NAME, resp.headers['Server']), "Service name '%s' is missing from the 'Server' in the headers; 'Server' is %s" %(search.endpoint.rest_endpoint_handler.SERVICE_NAME, resp.headers['Server']))
