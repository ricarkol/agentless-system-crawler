import gzip, csv, json, sys
from collections import namedtuple

Feature = namedtuple('Feature', ['type', 'resource', 'value'])
csv.field_size_limit(sys.maxsize)  # necessary to handle large value fields

with gzip.open('./frame.gz', 'r') as fd:      
    csv_reader = csv.reader(fd, delimiter='\t', quotechar="'")
    for row in csv_reader:
        # read one feature
        feature = Feature(row[0], json.loads(row[1]), json.loads(row[2]))
        if row[0] == 'disk' or row[0] == "os":
            # access the feature fields as: feature.type, feature.resource, feature.value
            print feature.type, feature.resource, feature.value