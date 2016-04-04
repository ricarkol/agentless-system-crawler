# Methods for determining how a feature has evolved. 
# Used to determine whether two instances of the same feature (matching keys) are equal or have changed. 

# TODO A feature class should be created and these methods should be part of such a class
# TODO Accordingly, the new feature class must be used throughout the code (e.g., in the diff/get_frame/etc logic.

def compare(f_instance1, f_instance2):
    if f_instance1['feature_type'] == 'process':
        return __process_comparator(f_instance1, f_instance2)
    return f_instance1['contents_hash'] != f_instance2['contents_hash']

def __process_comparator(p_instance1, p_instance2):
    pass