#!/usr/bin/env python

'''
@author: Nilton Bila
@author: Sastry Duri, adopted for vulnerability annotator for kafka listening interface
@author: Byungchul Tak, adapted this to compliance.
(c) IBM Research 2015
'''
import os
import re
import csv
import pickle
import fileinput
import subprocess
import calendar
import ConfigParser
import stat
import sys
import time
from collections import defaultdict
from kafka import KafkaClient, SimpleProducer, KeyedProducer
import uuid
import argparse
import csv
import logging
import logging.handlers
import signal
from multiprocessing import Pool
from cStringIO import StringIO

from pykafka.exceptions import ProduceFailureError


import json
    
import timeout
import kafka as kafka_python
import pykafka
import datetime

from va_python_base.KafkaInterface import KafkaInterface

from compliance_utils import *

logger_file = "/var/log/cloudsight/compliance-annotator.log"
PROCESSOR_GROUP = "compliance_annotator"


def sigterm_handler(signum=None, frame=None):
    print 'Received SIGTERM signal. Goodbye!'
    sys.exit(0)
signal.signal(signal.SIGTERM, sigterm_handler)


def UncrawlNamespaceFromKafkaFrame(in_metadata_param, files, configs, packages, logger):

    in_namespace = in_metadata_param['namespace']
    in_owner_namespace = in_metadata_param['owner_namespace']
    in_tm = in_metadata_param['timestamp']

    # Search if data already exists or not.
    subdir_list = os.listdir(temporary_directory+"/")
    for subdir in subdir_list:
        if re.match("compliance-[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}", subdir):
            metadata_filename = temporary_directory+"/"+subdir+"/__compliance_metadata.txt"
            if os.path.exists(metadata_filename):
                #f = open(metadata_filename,'r')
                #fcontent = f.readlines()
                #f.close()
                #f_nm = fcontent[0].strip()
                #f_tm = fcontent[1].strip()
                #f_onm = fcontent[2].strip()

                # read from json file
                metadata_dict = json.load(open(metadata_filename))
                f_nm = metadata_dict['namespace']  # namespace
                f_tm = metadata_dict['timestamp']  # timestamp
                f_onm = metadata_dict['owner_namespace'] # owner_namespace == tenant

                if f_nm==in_namespace and f_tm==in_tm:
                    print "Uncrawled data found!", in_namespace, in_tm
                    print "Directory path:", subdir
                    return 0

    logger.info(in_metadata_param['uuid']+" Uncrawling for "+in_namespace+" "+in_tm)

    prefix = temporary_directory+"/compliance-"+str(uuid.uuid4())
    logger.info(in_metadata_param['uuid']+" uncrawl directory prefix:"+prefix)

    #######################
    # Uncrawl File Feature
    for f in files:
        #print f['size']
        #print f['ctime']
        #print f['name']
        #print f['gid']
        #print f['mtime']
        #print f['uid']
        #print f['atime']
        #print f['type']
        fmode = f['mode']
        filepath = f['path']

        if stat.S_ISDIR(fmode):
            filepath = filepath+"/"

        # TODO: I'm ignoring any entry that contains non-ascii character.
        filepath_ascii = filepath.encode('ascii',errors='ignore')
        if filepath_ascii != filepath:
            continue

        try:
            if not os.path.exists( prefix + os.path.dirname(filepath) ):
                os.makedirs(prefix + os.path.dirname(filepath))
        except OSError as exception:
            print "WARNING: os.makedirs failed for "+prefix + os.path.dirname(filepath)
            continue

        if stat.S_ISREG(fmode):
            cfilename = prefix + filepath
            cfile = open(cfilename,'w')
            #cfile.write(data[filepath]['contents_hash'].encode("UTF-8")) # Write garbage to the file
            cfile.write("") # Write garbage to the file
            cfile.close()

        # In the os.makedirs function, I don't pass fmode parameter because, in Python 2.6, it tries to apply the mode to
        # all the directories being created, not only the last dir or file. So, I am calling os.chmod here separately.
        # TODO: I need to change mode in two phase. In the first phase, I change the permission of files.
        # Then, in the second phase, I change the permission of directories. If I change the permission of directories first, I may not be
        # able to create files that should go into the directory.
        if stat.S_ISREG(fmode):
            os.chmod(prefix + filepath, fmode)

    logger.info(in_metadata_param['uuid']+" files recreated in local file system")

    # Go through the second pass and update the mode of directories
    for f in files:
        fmode = f['mode']
        filepath = f['path']

        # TODO: I'm ignoring any entry that contains non-ascii character.
        filepath_ascii = filepath.encode('ascii',errors='ignore')
        if filepath_ascii != filepath:
            continue

        try:
            if stat.S_ISDIR(fmode):
                os.chmod(prefix + filepath, fmode)
        except OSError as exception:
            logger.info("WARNING: os.chmod failed for "+prefix + filepath)
            continue

    logger.info(in_metadata_param['uuid']+" file mode udpated")

    ############################
    # Uncrawl Config Feature
    for c in configs:

        filepath = c['path']
        content = c['content']

        # TODO: I'm ignoring any entry that contains non-ascii character.
        filepath_ascii = filepath.encode('ascii',errors='ignore')
        if filepath_ascii != filepath:
            continue

        try:
            if not os.path.exists( prefix + os.path.dirname(filepath) ):
                os.makedirs(prefix + os.path.dirname(filepath))
        except OSError as exception:
            logger.info("WARNING: os.makedirs failed for "+prefix + os.path.dirname(filepath))
            continue

        cfilename = prefix + filepath
        cfile = open(cfilename,'w')
        #cfile.seek(0)
        #cfile.truncate(0)
        cfile.write(content.encode("UTF-8"))
        cfile.close()

    logger.info(in_metadata_param['uuid']+" config file content filled in")

    # Create tmp directory under ${prefix} directory so that shell script can use tmp directory
    try:
        if not os.path.exists( prefix + "/tmp" ):
            os.makedirs( prefix + "/tmp" )
    except OSError as exception:
        logger.info("WARNING: os.makedirs failed for "+prefix + "/tmp")

    ##########################
    # Uncrawl Package Feature
    packages_filename = prefix+"/__compliance_packages.txt"
    if not os.path.exists(os.path.dirname(packages_filename)):
        os.makedirs(os.path.dirname(packages_filename))
    f = open(packages_filename,'w+')
    for p in packages:
        pkgversion = p['pkgversion']
        pkgname = p['pkgname']
        f.write(pkgname+" "+pkgversion+"\n")
    f.close()

    #######################
    # Create metadata file
    metadata_filename = prefix+"/__compliance_metadata.txt"
    if not os.path.exists(os.path.dirname(metadata_filename)):
        os.makedirs(os.path.dirname(metadata_filename))
    #f = open(metadata_filename,'w+')
    #f.write(in_namespace+"\n")
    #f.write(in_tm+"\n")
    #f.write(in_owner_namespace+"\n")
    #f.close()
    json.dump(in_metadata_param, open(metadata_filename,'w+'))
    logger.info(in_metadata_param['uuid']+" metadata file created")
    return prefix

def annotation_worker(param):
    rule_id = param[0]
    nm = param[1]
    tm = param[2]
    rid = param[3]
    local_uuid = param[4]

    os.chdir(annotator_home)
    cmd = "./Comp."+rule_id+".py "+nm+" "+tm+" "+str(rid)

    # 2015 Aug 19th, btak: I tried creating local_logger for each worker, but it turned out that I was able to use 'logger' without creating new logger.
    #log_dir = os.path.dirname(logger_file)
    #if not os.path.exists(log_dir):
    #    os.makedirs(log_dir)
    #    os.chmod(log_dir,0755)
    #format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    #logging.basicConfig(format=format, level=logging.INFO)
    #local_logger = logging.getLogger(__name__)

    #print "#",cmd
    logger.info(local_uuid+" 08 "+cmd)

    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output=""
    for line in p.stdout.readlines():
        output = output + line.strip()

    return output


# Package feature data example syntax
#[
#  {
#        u'pkgversion': u'3.113+nmu3ubuntu3', 
#        u'pkgname': u'adduser', 
#        u'pkgsize': u'644', 
#        u'installed': None
#    }
#, {
#        u'pkgversion': u'1.0.1ubuntu2.6', 
#        u'pkgname': u'apt', 
#        u'pkgsize': u'3576', 
#        u'installed': None
#    }
#, {
#        u'pkgversion': u'1.0.1ubuntu2.6', 
#        u'pkgname': u'apt-utils', 
#        u'pkgsize': u'668', 
#        u'installed': None
#    }
#]


def process_message(kafka_url, kafka_zookeeper_port, logger, receive_topic, publish_topic, notify_topic, instance_id):

    client = KafkaInterface(kafka_url, kafka_zookeeper_port, logger, receive_topic, publish_topic, notify_topic, PROCESSOR_GROUP)

    while True:
        try:
            for data in client.next_frame():

                files = []
                configs = []
                packages = []
                osinfo = []
                configparam = []
                stream = StringIO(data)
                csv.field_size_limit(sys.maxsize) # required to handle large value strings
                csv_reader = csv.reader(stream, delimiter='\t', quotechar="'")
                metadata = None
                for ftype, fkey, fvalue in csv_reader:
                    if ftype == 'file':
                        files.append(json.loads(fvalue))
                    if ftype == 'config':
                        configs.append(json.loads(fvalue))
                    if ftype == 'package':
                        packages.append(json.loads(fvalue))
                    if ftype == 'os':
                        osinfo.append(json.loads(fvalue))
                    if ftype == 'configparam':
                        configparam.append(json.loads(fvalue))
                    if not metadata and ftype == 'metadata':
                        metadata = json.loads(fvalue)
                stream.close()

                # Skip unrecognizable frames.
                if not metadata==None and not 'namespace' in metadata.keys():
                    logger.info("Frame with no namespace detected. Skipping.")
                    continue
                if not metadata==None and not 'uuid' in metadata.keys():
                    logger.info("Frame with no uuid detected. Skipping. namespace="+metadata['namespace'])
                    continue

                logger.info(metadata['uuid']+" NEW_FRAME -- "+str(metadata))
                log_message=""
                log_message=log_message+"len(files):"+str(len(files))
                log_message=log_message+" ,len(configs):"+str(len(configs))
                log_message=log_message+" ,len(packages):"+str(len(packages))
                log_message=log_message+" ,len(os):"+str(len(osinfo))
                log_message=log_message+" ,len(configparam):"+str(len(configparam))

                features = metadata.get('features',None)
                if features and 'configparam' in features:
                    log_message=log_message+" ,configparam:exists"
                else:
                    log_message=log_message+" ,configparam:nonexisting"
                logger.info(metadata['uuid']+" 00 "+log_message)

                # METADATA SAMPLE
                #{
                #    "compress": false,
                #    "container_image": "7bbe627dab2dfc2418c4a5c1ac7448dc308358fe4bee04737b6957cecd90c40c",
                #    "container_long_id": "1297d2946858a21276d1a2a4582110bcfa7d99656a051bf1db471f7237b9fd1d",
                #    "container_name": "8de9c596-fa6e-11e4-a978-0683fe7128d5",
                #    "features": "os,disk,file,package,config,dockerhistory,dockerps,dockerinspect",
                #    "namespace": "secreg2.sl.cloud9.ibm.com:5000/ubuntu-rkoller-15",
                #    "owner_namespace": "kollerr",
                #    "since": "EPOCH",
                #    "since_timestamp": 0,
                #    "system_type": "container",
                #    "timestamp": "2015-05-14T14:22:27-0500",
                #    "uuid": "8eda5cb8-fa6e-11e4-926e-0683fe7128d5"
                #}

                # METADATA SAMPLE
                #{
                #    u'since_timestamp': 0,
                #    u'container_long_id': u'None',
                #    u'features': u'os,disk,file,package,config,dockerhistory,dockerinspect',
                #    u'timestamp': u'2015-09-06T11:08:05.624194048Z',
                #    u'since': u'EPOCH',
                #    u'compress': False,
                #    u'system_type': u'container',
                #    u'container_name': u'70c1d27c-54b1-11e5-b087-062dcffc249f',
                #    u'container_image': u'',
                #    u'namespace': u'container/contaasfd/btak995',
                #    u'uuid': u'70c02990-54b1-11e5-a2a7-062dcffc249f'
                #}

                namespace = str(metadata['namespace']).strip()
                timestamp = str(metadata['timestamp']).strip()

                owner_namespace = "unknown"
                docker_image_registry = "unknown"
                docker_image_tag = "unknown"
                container_long_id = "unknown"
                docker_image_short_name = "unknown"
                docker_image_long_name = "unknown"
                container_name = "unknown"
                container_image = "unknown"
                metadata_uuid = "unknown"
                if 'owner_namespace' in metadata:
                    owner_namespace = str(metadata['owner_namespace']).strip()
                if 'docker_image_registry' in metadata:
                    docker_image_registry = metadata['docker_image_registry']
                if 'docker_image_tag' in metadata:
                    docker_image_tag = metadata['docker_image_tag']
                if 'container_long_id' in metadata:
                    container_long_id = metadata['container_long_id']
                if 'docker_image_short_name' in metadata:
                    docker_image_short_name = metadata['docker_image_short_name']
                if 'docker_image_long_name' in metadata:
                    docker_image_long_name = metadata['docker_image_long_name']
                if 'container_name' in metadata:
                    container_name = metadata['container_name']
                if 'container_image' in metadata:
                    container_image = metadata['container_image']
                if 'uuid' in metadata:
                    metadata_uuid = metadata['uuid']

                metadata_param = {
                    'namespace': namespace,
                    'timestamp': timestamp,
                    'owner_namespace': owner_namespace,
                    'docker_image_registry': docker_image_registry,
                    'docker_image_tag': docker_image_tag,
                    'container_long_id': container_long_id,
                    'docker_image_short_name': docker_image_short_name,
                    'docker_image_long_name': docker_image_long_name,
                    'container_name': container_name,
                    'container_image': container_image,
                    'uuid': metadata_uuid
                }

                notification_msg = { 
                    'processor': PROCESSOR_GROUP,
                    'instance-id': instance_id,
                    'status': 'start',
                    'namespace': namespace,
                    'timestamp': datetime.datetime.utcnow().isoformat()+'Z',
                    'timestamp_ms': int(time.time())*1000,
                    'uuid': metadata_uuid
                }

                features = metadata.get('features',None)
                if features and 'configparam' in features:
                    logger.info(metadata_uuid+" 01 Skipping configparam frame for "+namespace+" "+timestamp)
                    continue

                if len(files)==0 and len(configs)==0 and len(packages)==0 and len(osinfo)==0:
                    os_supported = False
                    logger.info(metadata_uuid+" 01 Unsupported OS detected! "+namespace+" "+timestamp+" "+str(osinfo))
                else:
                    os_supported = True
                    logger.info(metadata_uuid+" 01 OS supproted. "+namespace+" "+timestamp+" "+str(osinfo))

                #print "--namespace:       ", metadata_param['namespace']
                #print "--timestamp:       ", metadata_param['timestamp']
                #print "--owner_namespace: ", metadata_param['owner_namespace']
                #print "--docker_image_long_name: ", metadata_param['docker_image_long_name']
                #print "--docker_image_short_name: ", metadata_param['docker_image_short_name']
                #print "--docker_image_tag: ", metadata_param['docker_image_tag']

                logger.info(metadata_uuid+" 02 NAMESPACE              :"+ metadata_param['namespace'])
                logger.info(metadata_uuid+" 03 TIMESTAMP              :"+ metadata_param['timestamp'])
                logger.info(metadata_uuid+" 04 OWNER_NAMESPACE        :"+ metadata_param['owner_namespace'])
                logger.info(metadata_uuid+" 05 DOCKER_IMAGE_LONG_NAME :"+ metadata_param['docker_image_long_name'])
                logger.info(metadata_uuid+" 06 DOCKER_IMAGE_SHORT_NAME:"+ metadata_param['docker_image_short_name'])
                logger.info(metadata_uuid+" 07 DOCKER_IMAGE_TAG       :"+ metadata_param['docker_image_tag'])
                notify_msg_string = json.dumps(notification_msg)
                logger.info(notify_msg_string)
                client.notify(json.dumps(notify_msg_string), metadata_uuid, namespace)

                prefix = UncrawlNamespaceFromKafkaFrame(metadata_param, files, configs, packages, logger)

                ####
                ### this code is used to get the list of rules to run from scserver
                #####################
                #cmd = 'curl -s -k -XGET https://kasa.sl.cloud9.ibm.com:9292/api/get_rules?namespace=zzzz'
                #p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                #ret = ""
                #for line in p.stdout.readlines():
                #    ret = ret+line
                #cmp_data = []
                #if ret != "":
                #    cmp_data = json.loads(ret)
                #####################
                #print cmp_data

                #######################################################################
                ## Old code that didn't use parallel execution
                #request_id = 0 
                #for k in compliance_rule_list:
                #    #print "    ",k, namespace, timestamp
                #    cmd = "./Comp."+k+".py "+namespace+" "+timestamp+" "+str(request_id)
                #    print "#",cmd
                #    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                #    output=""
                #    for line in p.stdout.readlines():
                #        output = output + line.strip()
                #    request_id = request_id + 1
                #######################################################################

                ########################################################################
                ## Form the input data for pool execution
                #request_id = 1
                #data_for_pool = []
                #for k in compliance_rule_list:
                #    param = []
                #    param.append(k)
                #    param.append(namespace)
                #    param.append(timestamp)
                #    param.append(request_id)
                #    param.append(metadata_uuid)
                #    request_id = request_id + 1
                #    data_for_pool.append(param)
                #     
                #pool = Pool(processes=10)
                #it = pool.imap(annotation_worker, data_for_pool)
                #       
                ## Combine the output
                #msg_buf = StringIO()
                #msg_buf.write(json.dumps(metadata))
                #msg_buf.write('\n')
                #try:
                #    individual_compliance_output = it.next()
                #    while not individual_compliance_output==None:
                #        #print str(individual_compliance_output)
                #        msg_buf.write(individual_compliance_output)
                #        msg_buf.write('\n')
                #        individual_compliance_output = it.next()
                #except StopIteration:
                #    pass
                #pool.close()
                #pool.join()
                #logger.info(metadata_uuid+" 09 Compliance annotation finished for "+namespace+" "+timestamp)
                #######################################################################

                reqid = 1
                msg_buf = StringIO()
                msg_buf.write(json.dumps(metadata))
                msg_buf.write('\n')
                for k in compliance_rule_list:
                    output = DoComplianceChecking(prefix, k, namespace, timestamp, reqid, logger)
                    msg_buf.write(output.strip())
                    msg_buf.write('\n')
                    reqid = reqid + 1

                # Form the overall compliance result
                combined_output = msg_buf.getvalue()
                noncompliant_count = len(re.findall("\"compliant\":\"false\"",combined_output))
                compliant_count =len(re.findall("\"compliant\":\"true\"",combined_output))
                if noncompliant_count>0:
                    verdict_word="false"
                else:
                    verdict_word="true"

                if not os_supported:
                    compliant_count = -1
                    noncompliant_count = -1
                    verdict_word="unknown"

                last_output =""
                last_output = last_output + "{\"compliance_id\":\"Linux.0-0-a\"," # Linux.0-0a is a special compliance_id that is used for overall verdict
                last_output = last_output + "\"description\":\"Overall compliance verdict\","
                last_output = last_output + "\"compliant\":\""+verdict_word+"\","
                last_output = last_output + "\"reason\":\"Compliant count is "+str(compliant_count)+" and noncompliant count is "+str(noncompliant_count)+"\","
                last_output = last_output + "\"execution_status\":\"Success\","
                last_output = last_output + "\"total_compliance_rules\":"+str(len(compliance_rule_list))+","
                last_output = last_output + "\"compliance_violations\":"+str(noncompliant_count)+","
                last_output = last_output + "\"namespace\":\""+namespace+"\","
                last_output = last_output + "\"uuid\":\""+metadata_uuid+"\","
                last_output = last_output + "\"crawled_time\":\""+timestamp+"\","
                last_output = last_output + "\"compliance_check_time\":\""+datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")+"\","
                last_output = last_output + "\"request_id\":\"0\""
                last_output = last_output + "}"

                logger.info(metadata_uuid+" 10 "+last_output)

                # For some reason, combining this to one big output didn't work. It only worked when I called client.publish separately.
                msg_buf.write(last_output)
                msg_buf.write('\n')
                publish_message_string = json.dumps(msg_buf.getvalue())
                logger.info(publish_message_string)
                client.publish(publish_message_string, metadata_uuid, namespace)

                logger.info(metadata_uuid+" 11 Compliance verdict posted for "+namespace+" "+timestamp+" verdict:"+verdict_word)

                # Delete uncrawled data
                RemoveTempContent(prefix)
                logger.info(metadata_uuid+" 12 Uncrawl directory deleted "+prefix)

                notification_msg['status'] = 'completed'
                notification_msg['timestamp'] = datetime.datetime.utcnow().isoformat()+'Z'
                notification_msg['timestamp_ms'] = int(time.time())*1000
                notify_msg_string = json.dumps(notification_msg)
                logger.info(notify_msg_string)
                client.notify(notify_msg_string,metadata_uuid, namespace)

        except ProduceFailureError as error:
            logger.error("CANNOT PUBLISH TO KAFKA - COMPONENT DOWN")
            raise
            #component_down("/var/log/cloudsight/test",  "Could not publish to Kafka")

        except Exception as e:
            logger.exception(e)
            logger.error("Exiting with exception: %s" % e)
            raise

def component_down(test_file_location, message):
    with open(test_file_location, "a") as file:
        file.write("DOWN {} {}".format(time.time(), message))



if __name__ == '__main__':
    log_dir = os.path.dirname(logger_file)
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
        os.chmod(log_dir,0755)

    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    logging.basicConfig(format=format, level=logging.INFO)
    
    logger = logging.getLogger(__name__)
    
    fh = logging.handlers.RotatingFileHandler(logger_file, maxBytes=2<<27, backupCount=4)
    formatter = logging.Formatter(format)
    fh.setFormatter(formatter)
    logger.addHandler(fh)
    logger.propagate = False

    try:
        parser = argparse.ArgumentParser(description="")
        parser.add_argument('--kafka-url',  type=str, required=True, help='kafka url: host:port')
        parser.add_argument('--kafka-zookeeper-port',  type=str, required=True, help='kafka zookeeper port')
        parser.add_argument('--receive-topic', type=str, required=True, help='receive-topic')
        parser.add_argument('--notification-topic', type=str, required=True, help='topic to send process notification')
        parser.add_argument('--annotation-topic', type=str, required=True, help='topic to send annotations')
        parser.add_argument('--elasticsearch-url',  type=str, required=True, help='elasticsearch url: host:port')
        parser.add_argument('--annotator-home', type=str, required=True, help='full path of annotator')
        parser.add_argument('--instance-id',  type=str, required=True, help='instance id')

        args = parser.parse_args()
        elasticsearch_ip_port = args.elasticsearch_url
        kafka_ip_port = args.kafka_url
        kafka_zookeeper_port = args.kafka_zookeeper_port
        annotator_home = args.annotator_home
        process_message(args.kafka_url, kafka_zookeeper_port, logger, args.receive_topic, args.annotation_topic, args.notification_topic, args.instance_id)
    except Exception, e:
        print('Error: %s' % str(e))
        logger.exception(e) 
