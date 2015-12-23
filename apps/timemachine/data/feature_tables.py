from collections import OrderedDict

#
# Mapping of feature attributes to table column headers
#
feature_table_column_header_mappings = {
  'package': {
     'table_columns': ['Name', 'Version', 'Size'],
     'feature_attributes': ['pkgname', 'pkgversion', 'pkgsize']
   },
   'process': {
     'table_columns': ['Name', 'Pid', 'User', 'Full Command'],
     'feature_attributes': ['pname', 'pid', 'user', 'cmd']
   }
}

# 
# These attributes are attached to the <TABLE> tag of the HTML representation
#
html_table_attributes = {
  'class': 'table table-condensed table-striped',
  'style': 'font-size:12px;'
}


#
#   Helper functions used to construct tables of features with ordered, selected attributes 
# defined by feature_table_column_header_mappings
#

def get_feature_table_column_headers(feature_type):
    return feature_table_column_header_mappings[feature_type]['table_columns']
    
def get_feature_table_row(feature_type, feature):
    return [ feature[x] for x in feature_table_column_header_mappings[feature_type]['feature_attributes'] ]