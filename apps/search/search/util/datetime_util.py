import datetime
import dateutil.parser
import pytz
import re
import traceback

def get_date_from_iso_timestamp(timestamp):
    dt = dateutil.parser.parse(timestamp)
    return dt.date()

def get_delta_days(timestamp1, timestamp2):
    day1 = get_date_from_iso_timestamp(timestamp1)
    day2 = get_date_from_iso_timestamp(timestamp2)
    return (day2 - day1).days

def get_iso_timestamp_plus_delta_days(timestamp, day_span):
    dt = dateutil.parser.parse(timestamp)
    delta = datetime.timedelta(days=day_span)
    dt_plus_delta = dt + delta
    return validate_and_convert_timestamp(dt_plus_delta.isoformat())

def get_indices_list_from_iso_timestamps(timestamp1, timestamp2, index_prefix):
    date1 = get_date_from_iso_timestamp(timestamp1)
    delta_days = get_delta_days(timestamp1, timestamp2) + 1
    indices = [ get_index_from_date(date1 + datetime.timedelta(days=x), index_prefix) for x in range(0, delta_days) ]    
    return indices

def get_indices_list_from_iso_timestamp_dayspan(timestamp, day_span, index_prefix):
    dt1 = dateutil.parser.parse(timestamp)
    delta = datetime.timedelta(days=day_span)
    dt2 = dt1 + delta
    dt2_iso_str = dt2.isoformat()
    return get_indices_list_from_iso_timestamps(timestamp, dt2_iso_str, index_prefix) if delta.days > 0 else get_indices_list_from_iso_timestamps(dt2_iso_str, timestamp, index_prefix)
            
def get_index_from_date(date, index_prefix):
    return index_prefix + str(date).replace('-', '.')

def get_index_from_iso_timestamp(timestamp, index_prefix):
    dt = dateutil.parser.parse(timestamp)
    return index_prefix + str(dt.date()).replace('-', '.')

def is_valid_time_interval(timestamp1, timestamp2):
    dt1 = dateutil.parser.parse(timestamp1)
    dt2 = dateutil.parser.parse(timestamp2)
    delta = dt2 - dt1
    return delta.total_seconds() > 0

def compare_iso_timestamps(t1, t2):
    '''
    Returns an integer:
      * == 0   if the timestamps are equal
      * > 0    if t1 > t2
      * < 0    if t1 < t2   
    '''
    dt1 = dateutil.parser.parse(t1)
    dt2 = dateutil.parser.parse(t2)
    delta = dt1 - dt2
    return delta.total_seconds()

def validate_and_convert_timestamp(timestamp):
    try:
        # Initial regex matching to prevent dateutil.parser.parse() from accepting certain date formats
        valid_match = re.match('\d{4}-\d{2}-\d{2}T\d{2}:\d{2}', timestamp)
        if valid_match == None:
            return None
        
        dt = dateutil.parser.parse(timestamp)
        dt_str = dt.isoformat()
        new_dt_str = dt_str
        match_utc = re.match('.*Z$|.*[+-]00:00$', dt_str)
        if match_utc == None:
            # Need to convert timestamp to UTC 
            # This will work regardless of the original time zone (even if not local) 
            match_tz = re.match('.*([+-])(\d{2}):(\d{2})$', dt_str)
            tz_sign = match_tz.group(1)
            tz_hours = int(match_tz.group(2))
            tz_min = int(match_tz.group(3))
            td = datetime.timedelta(hours=tz_hours, minutes=tz_min)
            if tz_sign == '-':
                dt = dt + td
            else:
                dt = dt - td
            new_dt = dt.replace(tzinfo=pytz.timezone('UTC'))
            new_dt_str = new_dt.isoformat()
            # Make sure we remove the fields for seconds and subseconds when they are all zeroes    
            #new_dt_str = re.sub(':00(\.0*)?\+00:00', '+00:00', new_dt_str) 
        #else:
            # Return the original timestamp back when it is already in UTC, 
            #  but make sure we remove the fields for seconds and subseconds when they are all zeroes
            #new_dt_str = re.sub(':00(\.0*)?\+00:00', '+00:00', timestamp)
        return new_dt_str
            
    except Exception as e:
        print traceback.format_exc()
        return None