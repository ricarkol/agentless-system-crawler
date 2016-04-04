import json
import argparse
from cStringIO import StringIO
import collections
import index_client
import time
import  elasticsearch

ELASTIC_SEARCH_HOST = 'http://csdev.sl.cloud9.ibm.com:9200'

INDICES = [
    {'index_name' : 'vulnerabilityscan-today', 'doc_type' : 'vulnerabilityscan'},
    {'index_name': 'compliance-today', 'doc_type' : 'compliance' },
    {'index_name': 'config-today', 'doc_type': 'config_crawler'}
]
 

FlowEvent = collections.namedtuple('FlowEvent', 'processor status timestamp timestamp_ms instance_id namespace received_ts')

processing_stages =  ['registry-monitor', 'registry-upfdate', 'regcrawler', 'crawler', 'configindexer', 'vulnerability_annotator', \
                        'vulnerabilityscan_indexer', 'compliance_annotator', 'compliance_indexer']

FIRST_ALERT_WAIT_TIME = 300        # seconds
SECOND_ALERT_WAIT_TIME = 1200      # seconds
THIRD_ALERT_WAIT_TIME = 3600       # seconds
FINAL_PURGE_WAIT_TIME = 7200       # seconds
SLEEP_TIME=10

class FlowEventProcessor:

    def __init__(self, logger, moving_window_size=10, es_host='http://localhost:9200'):

        self.moving_window_size = moving_window_size
        self.es_host = es_host
        self.logger = logger

        self.process_stage_dqueues = {}
        self.process_stage_moving_avgs = {}
        for process_stage in processing_stages:
            self.process_stage_dqueues[process_stage] = collections.deque(maxlen=moving_window_size)
            self.process_stage_moving_avgs[process_stage] = 0.0

        self.first_alert_sent = {}
        self.second_alert_sent = {}
        self.third_alert_sent = {}

        self.pending_completion = {}
        self.flow_events = {}
        self.index_check_status = {}

    def add_notification(self, msg):

        '''
        When it sees the first event notification for given uuid, that event is added to pending_completion 
        '''
        flow_id = msg.get('uuid')
        if flow_id is None:
            return

        fe = FlowEvent(
            processor = msg.get('processor'), status = msg.get('status'), timestamp = msg.get('timestamp'),
            timestamp_ms = msg.get('timestamp_ms'), instance_id = msg.get('instance-id'), namespace = msg.get('namespace'),
            received_ts = int(time.time())
            )
    
        if flow_id not in self.flow_events:
            self.flow_events[flow_id] = []
            self.pending_completion[flow_id] =  fe
    
        flow_state = self.flow_events.get(flow_id)
        flow_state.append(fe)
    
    def compute_processing_time(self, flow_id, processor):

        start = -1
        completed = -1
        for flow_event in self.flow_events[flow_id]:
            if flow_event.processor == processor and flow_event.status == 'start':
                start = flow_event.timestamp_ms
            if flow_event.processor == processor and (flow_event.status == 'completed' or flow_event.status == 'error'):
                completed = flow_event.timestamp_ms

        if start != -1 and completed != -1:
            return completed - start
    
    def compute_average_completion_times(self, flow_id):
    
        for process_stage in processing_stages:
            process_time = self.compute_processing_time(flow_id, process_stage)
            if process_time:
                self.process_stage_dqueues[process_stage].append(process_time)
                _sum = float(sum(self.process_stage_dqueues[process_stage]))
                _len = len(self.process_stage_dqueues[process_stage])
                self.process_stage_moving_avgs[process_stage] = _sum/_len
    
    def check_status(self):
        '''
        For data flow recorded in pending_completion check whether index has received at least one
        document. If yes, then it considers data flow for that crawl complete
        and deletes that from pending_completion.
        '''
        client = index_client.IndexClient(elastic_host=self.es_host)

        for flow_id in self.pending_completion.keys():
            flow_event = self.pending_completion[flow_id]
            completed = True

            for index in INDICES:

                if flow_id in self.index_check_status and index['index_name'] in self.index_check_status[flow_id]:
                    continue     # don't make duplicate elasticsearch queries

                count = 0
                try:
                    count = client.get_result_count(
                        flow_event.namespace, flow_id,
                        index['index_name'], index['doc_type'])
                except elasticsearch.NotFoundError, e:
                    # immediately after initialization, before first document flows indexes
                    # don't exist. 
                    self.logger.info(str(e))
                    time.sleep(SLEEP_TIME)
    
                if count == 0:
                    completed = False # data not found in this index
                else:
                    if flow_id not in self.index_check_status:
                        self.index_check_status[flow_id] = {}

                    status = self.index_check_status[flow_id]
                    if index['index_name'] not in status:
                        status[index['index_name']] = int(time.time())
    
            if completed: # data found in all INDICES data flow is complete
                self.compute_average_completion_times(flow_id)
                self.purge_flow_event(flow_id)

    def purge_flow_event(self, flow_id):

        self.logger.info('purging flow_id={}'.format(flow_id))
        if flow_id in self.pending_completion:
            del self.pending_completion[flow_id]   
        if flow_id in self.index_check_status:
            del self.index_check_status[flow_id]
        if flow_id in self.flow_events:
            del self.flow_events[flow_id]

        if flow_id in self.third_alert_sent:
            del self.third_alert_sent[flow_id]
        if flow_id in self.second_alert_sent:
            del self.second_alert_sent[flow_id]
        if flow_id in self.first_alert_sent:
            del self.first_alert_sent[flow_id]
    

    def send_alert(self, flow_id, delay_time):
        out = { "description" :"delay_report",
                "delay": delay_time,
                "unit": "second",
                "events": self.flow_events[flow_id],
                "uuid": flow_id }
        self.logger.warn('{}'.format(json.dumps(out)))
        
    def print_event_log(self):

        self.check_status()
    
        moving_avg = []
        for process_stage in processing_stages:
            moving_avg.append({'component': process_stage, 
                                'time': '{:.2f}'.format( self.process_stage_moving_avgs[process_stage] ),
                                'window_size': len(self.process_stage_dqueues[process_stage])
                        })
        self.logger.info(json.dumps({"description": "moving_averages", "unit": "ms", "moving_averages" : moving_avg}))

        now = int(time.time())
        first_notification_cutoff = now - FIRST_ALERT_WAIT_TIME
        second_notification_cutoff = now - SECOND_ALERT_WAIT_TIME
        third_notification_cutoff = now - THIRD_ALERT_WAIT_TIME
        final_purge_cutoff = now - FINAL_PURGE_WAIT_TIME

        for flow_id in self.pending_completion.keys():

            flow_event = self.pending_completion[flow_id]

            if flow_event.received_ts <= final_purge_cutoff:
                self.purge_flow_event(flow_id)

            elif flow_event.received_ts <= third_notification_cutoff:
                if flow_id in self.third_alert_sent:
                    continue 
                else:
                    self.third_alert_sent[flow_id] = now
                    self.send_alert(flow_id, THIRD_ALERT_WAIT_TIME)

            elif flow_event.received_ts <= second_notification_cutoff:
                if flow_id in self.second_alert_sent:
                    continue 
                else:
                    self.second_alert_sent[flow_id] = now
                    self.send_alert(flow_id, SECOND_ALERT_WAIT_TIME)

            elif flow_event.received_ts <= first_notification_cutoff:
                if flow_id in self.first_alert_sent:
                    continue
                else:
                    self.first_alert_sent[flow_id] = now
                    self.send_alert(flow_id, FIRST_ALERT_WAIT_TIME)

