import sys
import logging
import logging.handlers 
import time
import optparse
import random

logger = None # logger
cmdlineparams = None # cmdline options
eventlineheadersize = sys.getsizeof('2014-06-02 06:57:34,970 - __main__ - INFO - eventCount=1, eventLineSizeBreakup(inbytes)<msgsize=53,headersize=138>, eventMessage=')

def genEventMessage():
	# Generate message composed of multiple time.time() blocks, such that the resulting eventline.sizeinbytes will be approx equal to the specified event-volume
        #field = time.time()
	message = '<'
	while ( sys.getsizeof(message) + eventlineheadersize ) < ( cmdlineparams.event_volume * 1000 ) :
		field = random.random()
        	message = message + str(field) + ','
	message = message + '>'
    	return message
        

def genLogData():
	# We will first test the size of the message
        #logger.info('Scaletesting genLogData() infinite loop starting with params <event_rate=' + str(cmdlineparams.event_rate) + ', event_volume=' + str(cmdlineparams.event_volume) + '>');
        eventInterval = 1.0 / cmdlineparams.event_rate  # make sure it is 1.0 and not 1 to ensure floating point division
        eventCount = 0
	while True : 
        	eventCount = eventCount + 1
        	eventMessage = genEventMessage()
		logger.info('eventCount=' + str(eventCount) + ', eventLineSizeBreakup(inbytes)<msgsize=' + str(sys.getsizeof(eventMessage)) + ',headersize=' + str(eventlineheadersize) + '>' + ', eventMessage=' + eventMessage)
        	time.sleep(eventInterval)
    	return 


if __name__ == '__main__':
       
 	# Parse the commandline params
	parser = optparse.OptionParser()
        parser.add_option('--event-rate', dest="event_rate", type=float, default=0.1, help='Event Rate (#events/sec)')
        parser.add_option('--event-volume', dest="event_volume", type=int, default=1, help='Event Volume (size in KB per event line in log)')
	parser.add_option('--logdatafile', dest="logdatafile", type=str, default='SCALETESTING_LOGDATA.log', help='Generated Logdata file)')
        cmdlineparams, remainder = parser.parse_args()
        
	# Configure the logger	
	#logging.basicConfig(filename=cmdlineparams.logdatafile, filemode='w', format='%(asctime)s %(levelname)s : %(message)s', level=logging.DEBUG)
	logger = logging.getLogger(__name__)
        logger.setLevel(logging.DEBUG)
	logRotatingHandler = logging.handlers.RotatingFileHandler(cmdlineparams.logdatafile, maxBytes=1000000000, backupCount=1)  # 1 GB main log + 1 olderrollinglog
	logFormatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
	logRotatingHandler.setFormatter(logFormatter)
	logger.addHandler(logRotatingHandler)

	# Generate log data in infinite loop       
    	genLogData()

