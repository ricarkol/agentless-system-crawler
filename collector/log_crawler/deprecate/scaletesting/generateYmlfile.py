import optparse
from jinja2 import Template


cmdlineparams = None

ymlTemplate = '''
cloudsight:
  broker_host: '{{param_broker_host}}'
  broker_port: {{param_broker_port}}
  
namespace_prefix:
  tenant_id: '{{param_tenant_id}}'
  system_prefix: '{{param_system_prefix}}'

log_crawler:
  batch: true
  batch_events: {{param_batch_events}}
  batch_timeout: {{param_batch_timeout}}
  format: 'message'

log_files:
 {% for i in range(0, param_numlogfiles) %}
  -
    path: '{{param_logcrawldir}}/scaletesting.{{i}}.log'
    type: 'scaletesting'
    namespace_system_suffix: '' 
 {% endfor %}
'''


def generateYmlfile():
	t = Template(ymlTemplate)
	generatedYmlfiledata = t.render( \
				     param_broker_host=cmdlineparams.broker_host, \
				     param_broker_port=cmdlineparams.broker_port, \
				     param_tenant_id=cmdlineparams.tenant_id, \
                                     param_system_prefix=cmdlineparams.system_prefix, \
				     param_batch_events=cmdlineparams.batch_events, \
                                     param_batch_timeout=cmdlineparams.batch_timeout, \
				     param_numlogfiles=cmdlineparams.numlogfiles, \
                                     param_logcrawldir=cmdlineparams.logcrawldir \
				    )
	# Write the generatedTemplate to the yml file
	with open(cmdlineparams.ymlfilename,'w') as f:
		f.write(generatedYmlfiledata) 
	return 


if __name__ == '__main__':
	# Parse the commandline params
	parser = optparse.OptionParser()
        parser.add_option('--broker-host', dest="broker_host", type=str, default='localhost', help='Logstash-crawler broker_host param')
        parser.add_option('--broker-port', dest="broker_port", type=int, default=8080, help='Logstash-crawler broker_port param')
	parser.add_option('--tenant-id', dest="tenant_id", type=str, default='scaletesting', help='Logstash-crawler tenant_id param')
        parser.add_option('--system-prefix', dest="system_prefix", type=str, default='scaletestinglaptop', help='Logstash-crawler system_prefix param')
        parser.add_option('--batch-events', dest="batch_events", type=int, default=1, help='Logstash-crawler batch_events param')
        parser.add_option('--batch-timeout', dest="batch_timeout", type=int, default=1, help='Logstash-crawler batch_timeout param')
        parser.add_option('--logcrawldir', dest="logcrawldir", type=str, default='/vagrant/scaletesting/log_crawler/logfilesbeingcrawled/', help='ScaleTesting logdirectory containing files to crawl')
        parser.add_option('--numlogfiles', dest="numlogfiles", type=int, default=5, help='ScaleTesting #logfiles to crawl')
        parser.add_option('--ymlfilename', dest="ymlfilename", type=str, default='SCALETESTING_LOGCRAWLERCONFIG.yml', help='Output Yml filename')
        cmdlineparams, remainder = parser.parse_args()

	print ">>> Generating Logstash-crawler .yml configfile=", cmdlineparams.ymlfilename
	generateYmlfile()	



