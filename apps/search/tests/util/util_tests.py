import unittest
import search.util.datetime_util
import search.data.configdata_handler

class UtilTestCases(unittest.TestCase):
    def test_timestamp_conversions(self):
        edt_time1 = '2015-02-03T10:03-05:00'
        expected_utc_time = '2015-02-03T15:03:00+00:00'
        
        edt_time2 = '2015-02-03T10:03:55-05:00'
        expected_utc_time2 = '2015-02-03T15:03:55+00:00'
        
        time3 = '2015-02-03T10:03:55-03:00'
        expected_utc_time3 = '2015-02-03T13:03:55+00:00'
        
        time4 = '2015-02-03T10:03:00+03:00'
        expected_utc_time4 = '2015-02-03T07:03:00+00:00'
        
        utc_time1 = '2015-02-03T15:03Z'
        expected_utc_time1 = '2015-02-03T15:03:00+00:00'
        
        utc_time2 = '2015-02-03T15:03+00:00'
        expected_t2 = '2015-02-03T15:03:00+00:00'
        
        edt_time_3 = '2015-02-28T23:55-05:00'
        expected_utc_time_5 = '2015-03-01T04:55:00+00:00'
        
        unparsable_time1 = '2015-02-0310:03-05:00'
        unparsable_time2 = '015-02-03T10:03-05:00'
        unparsable_time3 = '15-02-03T10:03-05:00'
        
        ret_time = search.util.datetime_util.validate_and_convert_timestamp(edt_time1)
        self.assertEqual(ret_time, expected_utc_time, 'Incorrect datetime conversion.')
        
        ret_time = search.util.datetime_util.validate_and_convert_timestamp(edt_time2)
        self.assertEqual(ret_time, expected_utc_time2, 'Incorrect datetime conversion.')
        
        ret_time = search.util.datetime_util.validate_and_convert_timestamp(time3)
        self.assertEqual(ret_time, expected_utc_time3, 'Incorrect datetime conversion.')
        
        ret_time = search.util.datetime_util.validate_and_convert_timestamp(time4)
        self.assertEqual(ret_time, expected_utc_time4, 'Incorrect datetime conversion.')
        
        ret_time = search.util.datetime_util.validate_and_convert_timestamp(utc_time1)
        self.assertEqual(ret_time, expected_utc_time1, 'Incorrect datetime conversion.')
        
        ret_time = search.util.datetime_util.validate_and_convert_timestamp(utc_time2)
        self.assertEqual(ret_time, expected_t2, 'Incorrect datetime conversion.')
        
        ret_time = search.util.datetime_util.validate_and_convert_timestamp(unparsable_time1)
        self.assertEqual (ret_time, None, 'Incorrect datetime conversion.')
        
        ret_time = search.util.datetime_util.validate_and_convert_timestamp(unparsable_time2)
        self.assertEqual (ret_time, None, 'Incorrect datetime conversion.')
        
        ret_time = search.util.datetime_util.validate_and_convert_timestamp(unparsable_time3)
        self.assertEqual (ret_time, None, 'Incorrect datetime conversion.')
        
        ret_time = search.util.datetime_util.validate_and_convert_timestamp(edt_time_3)
        self.assertEqual (ret_time, expected_utc_time_5, 'Incorrect datetime conversion.')
        
        ret_time = search.util.datetime_util.validate_and_convert_timestamp(expected_utc_time_5)
        self.assertEqual (ret_time, expected_utc_time_5, 'Incorrect datetime conversion.')
    
    def test_timestamp_deltas(self):
        timestamp = "2015-02-28T10:00-05:00"
        day_span = 2
        t_plus_delta = search.util.datetime_util.get_iso_timestamp_plus_delta_days(timestamp, day_span)
        expected_timestamp = "2015-03-02T15:00:00+00:00"
        self.assertEqual(t_plus_delta, expected_timestamp, 'Expected time %s but got time %s' % (expected_timestamp, t_plus_delta))
        
        timestamp = "2015-02-28T10:00Z"
        t_plus_delta = search.util.datetime_util.get_iso_timestamp_plus_delta_days(timestamp, day_span) 
        expected_timestamp = "2015-03-02T10:00:00+00:00"
        self.assertEqual(t_plus_delta, expected_timestamp, 'Expected time %s but got time %s' % (expected_timestamp, t_plus_delta))
    
    def test_compare_iso_timestamps(self):
        t1 = "2015-02-28T10:00-05:00"
        t2 = "2015-02-28T10:30-05:00"
        
        t3 = "2015-02-28T15:30+00:00"
        t4 = "2015-02-28T15:30Z"
        t5 = "2015-02-28T15:40+00:00"
        
        t6 = "2015-02-28T10:10-05:00"
        t7 = "2015-02-28T10:15-05:00"
        t8 = "2015-02-28T10:20-05:00"
        
        self.assertGreater(search.util.datetime_util.compare_iso_timestamps(t2, t1) , 0, '%s must be greater than %s' % (t2, t1))
        self.assertLess(search.util.datetime_util.compare_iso_timestamps(t1, t2) , 0, '%s must be less than %s' % (t1, t2))
        self.assertEqual(search.util.datetime_util.compare_iso_timestamps(t1, t1), 0, '%s must be equal to %s' % (t1, t1))
        self.assertEqual(search.util.datetime_util.compare_iso_timestamps(t2, t2), 0, '%s must be equal to %s' % (t2, t2))
        
        self.assertEqual(search.util.datetime_util.compare_iso_timestamps(t2, t3), 0, '%s must be equal to %s' % (t2, t3))
        self.assertEqual(search.util.datetime_util.compare_iso_timestamps(t3, t4), 0, '%s must be equal to %s' % (t3, t4))
        self.assertGreater(search.util.datetime_util.compare_iso_timestamps(t5, t1) , 0, '%s must be greater than %s' % (t5, t1))
        
        delta1 = search.util.datetime_util.compare_iso_timestamps(t6, t1)
        delta2 = search.util.datetime_util.compare_iso_timestamps(t2, t6)
        self.assertLess(delta1, delta2, '%s must be closer to %s than it is to %s' %(t6, t1, t2))
        
        delta3 = search.util.datetime_util.compare_iso_timestamps(t8, t1)
        delta4 = search.util.datetime_util.compare_iso_timestamps(t4, t8)
        self.assertGreater(delta3, delta4, '%s must be closer to %s than it is to %s' %(t8, t4, t1))
    
    def test_indices_calculations(self):
        timestamp = "2015-02-28T10:00-05:00"
        days_span = 2
        index_prefix = search.data.configdata_handler.ConfigDataHandler.CONFIG_INDEX_PREFIX
        indices_list = search.util.datetime_util.get_indices_list_from_iso_timestamp_dayspan(timestamp, days_span, index_prefix)
        expected_dates = ['2015.02.28', '2015.03.01', '2015.03.02']
        expected_indices = [ index_prefix + x for x in expected_dates ]
        self.assertEqual(indices_list, expected_indices, 'Expected indice list %s but got %s instead.' % (expected_indices, indices_list))
        
        days_span = -2
        expected_dates = ['2015.02.26', '2015.02.27', '2015.02.28']
        expected_indices = [ index_prefix + x for x in expected_dates ]
        indices_list = search.util.datetime_util.get_indices_list_from_iso_timestamp_dayspan(timestamp, days_span, index_prefix)
        self.assertEqual(indices_list, expected_indices, 'Expected indice list %s but got %s instead.' % (expected_indices, indices_list))
        
        days_span = 0
        expected_dates = ['2015.02.28']
        expected_indices = [ index_prefix + x for x in expected_dates ]
        indices_list = search.util.datetime_util.get_indices_list_from_iso_timestamp_dayspan(timestamp, days_span, index_prefix)
        self.assertEqual(indices_list, expected_indices, 'Expected indice list %s but got %s instead.' % (expected_indices, indices_list))