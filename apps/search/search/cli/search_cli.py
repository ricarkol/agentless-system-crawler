import argparse
import config

class SearchCLI:
    @staticmethod
    def parse_arguments():
        parser = argparse.ArgumentParser(
            description='CloudSight Elasticsearch search service.')
        
        parser.add_argument('--port', type=int, default=5000, metavar='<port>',
            help='The port to which the search service will listen')
        parser.add_argument('--es', type=str, default='localhost:9200', metavar='<elasticsearch_cluster>',
            help='Comma-separated list of the form "<host_1:port_1>, <host_2:port_2>, ..., <host_n:port_n>" indicating the target Elasticsearch cluster')
    
        parser.add_argument('-v', '--verbose', action='store_true', help='Turns on debug-level logging')
        
        return config.Config(parser.parse_args())