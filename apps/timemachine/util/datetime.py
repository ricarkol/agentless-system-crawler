import dateutil.parser

def get_index_from_iso_timestamp(timestamp, index_prefix):
    dt = dateutil.parser.parse(timestamp)
    return index_prefix + str(dt.date()).replace('-', '.')