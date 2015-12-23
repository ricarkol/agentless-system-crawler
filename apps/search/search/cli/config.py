class Config:
    '''
    This class encapsulates the configuration of the search service.
    '''
    DEFAULT_PORT = 5000
    DEFAULT_ES_CLUSTER = ['localhost:9222']
    
    def __init__(self, cli_parsed_args=None):
        '''
        Arguments:
         - cli_parsed_args: Object produced by ArgumentParser after parsing the command-line arguments. See search_cli.SearchCLI.
        '''
        self.__properties = {}
        if cli_parsed_args:
            self.__properties['port'] = cli_parsed_args.port
            self.__properties['es_cluster'] = cli_parsed_args.es.replace(' ', '').split(',')
            self.__properties['verbose'] = cli_parsed_args.verbose
    
    def get_port(self):
        '''
        Returns an integer representing the port to which the service is listening.
        '''
        return self.__properties['port']
    
    def set_port(self, port):
        '''
        Arguments:
         - port: Port to which the service is listening.
        '''
        self.__properties['port'] = port
    
    def get_elasticsearch_cluster(self):
        '''
        Returns a list (array) where each element is a string of the form 'host:port' representing the Elasticsearch cluster.
        '''
        return self.__properties['es_cluster']
    
    def set_elasticsearch_cluster(self, es_cluster):
        '''
        Arguments:
         - es_cluster: String with comma-separated list of tuples of the form '<host1>:<port1>, <host2>:port2,...'
        '''
        self.__properties['es_cluster'] = es_cluster.replace(' ', '').split(',')
    
    def is_verbose(self):
        return self.__properties['verbose']
    
    def set_verbose(self, verbose):
        self.__properties['verbose'] = verbose
