import yaml
import tenjin
from tenjin.helpers import *

class LogCrawlerConfig:
    '''
    This class provides a representation of the log crawler configuration
    '''
        
    _LOG_FILES = 'log_files'
    _NAMESPACE_PREFIX = 'namespace_prefix'
    _NAMESPACE_TENANT_ID = 'tenant_id'
    _NAMESPACE_SYSTEM_PREFIX = 'system_prefix'
    _CLOUDSIGHT = 'cloudsight'
    _BROKER_HOST = 'broker_host'
    _BROKER_PORT = 'broker_port'
    _LOG_CRAWLER = 'log_crawler'
    _BATCH = 'batch'
    _BATCH_EVENTS = 'batch_events'
    _BATCH_TIMEOUT = 'batch_timeout'
    _FORMAT = 'format'
    _REPLAY = 'replay'
    
    def __init__(self, crawler_config_file):
        """
        Converts a config file in YAML format into an in-memory object.
        
          Arguments:
            - crawler_config_file: Path to the log crawler config file 
        """
        f = open(crawler_config_file, 'r')
        self._properties = yaml.load(f)
        f.close()
    
    def generate_logstash_config(self,  shipper_template):
        """
        Generates a Logstash config file that will make Logstash send log events to CloudSight.
        
          Arguments:
            - shipper_template: Path to the template file used to generate the Logstash configuration
          Returns:
            A string representing the Logstash configuration  
        """
        engine = tenjin.Engine()
        tenjin.Engine.cache = tenjin.MemoryCacheStorage()
        shipper_conf = engine.render(shipper_template, {'crawler_config': self._properties})
        return shipper_conf
    
    def get_log_files_info(self):
        """
        Returns an array of dictionaries containing information about each log file of interest.
        Each element of the array holds the following pieces of information:
          ** path to the log file (required);
          ** type of log (optional);
          ** namespace_system_suffix
        
        Note that namespace_system_suffix is a string that will be appended to the system portion of the namespace 
        to which the events of the corresponding log file will be sent. 
        
        Note that the resulting namespace string that the crawler constructs will comprise:
        
        <namespace_tenant_id>:<namespace_system_prefix><namespace_system_suffix>/<host>[/<log type>]/<log_file_path> 
        
        If log type is provided in the config file, it is used by the crawler when building the namespace.
        """
        return self._properties[LogCrawlerConfig._LOG_FILES]
    
    def get_namespace_tenant_id(self):
        """
        Returns a string representing the tenant id portion of the namespace. 
        """
        return self._properties[LogCrawlerConfig._NAMESPACE_PATTERN][LogCrawlerConfig._NAMESPACE_TENANT_ID]
    
    def get_namespace_system_prefix(self):
        """
        Returns a string representing the prefix of the system portion of the namespace. 
        """
        return self._properties[LogCrawlerConfig._NAMESPACE_PATTERN][LogCrawlerConfig._NAMESPACE_SYSTEM_PREFIX]

    def get_cloudsight_broker_host(self):
        """
        Returns the hostname of the Cloudsight broker 
        """
        return self._properties[LogCrawlerConfig._CLOUDSIGHT][LogCrawlerConfig._BROKER_HOST]

    def get_cloudsight_broker_port(self):
        """
        Returns Cloudsight broker port 
        """
        return self._properties[LogCrawlerConfig._CLOUDSIGHT][LogCrawlerConfig._BROKER_PORT]    