'''
Generates the Logstash configuration file needed to get the desired log events into CloudSight.
'''

import sys
import log_crawler_config        
    

def main():
    crawler_config_file_path = sys.argv[1]
    shipper_config_template = sys.argv[2]
    crawler_config = log_crawler_config.LogCrawlerConfig(crawler_config_file_path)
    print crawler_config.generate_logstash_config(shipper_config_template)

if __name__ == '__main__':
    main()