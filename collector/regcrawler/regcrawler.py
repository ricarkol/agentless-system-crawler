#!/usr/bin/env python

'''
This program crawls specified container cloud registry and downloads and crawls 
any new images to local repository.

(c) IBM Research 2015
'''

#prereqs: pip install requests, docker-py, pykafka, kafka-python
import argparse
import sys
import logging
import logging.handlers
import requests
import time
import subprocess
import re
import uuid
from docker import client, errors
import os
import urlparse
import csv
import datetime
import kafka as kafka_python
import pykafka
from functools import wraps
import errno
import signal
import ast

try:
    import simplejson as json
except:
    import json

log_file = "/var/log/regcrawler.log"
child_log_file = "/var/log/regcrawler_child.log"

http_request_timeout= 120
try:
    ice_config = os.path.join(os.getenv('HOME'), '.cf/config.json')
except AttributeError:
    ice_config = '/.cf/config.json'

logger              = logging
processor_group     = 'regcrawler'

class TimeoutError(Exception):
    pass

class DeviceError(Exception):
    pass

class RegistryError(Exception):
    pass

class CrawlerError(Exception):
    pass

def timeout(seconds=5, msg=os.strerror(errno.ETIMEDOUT)):
    def decorator(func):
        def timeout_handler(sig, frame):
            raise TimeoutError(msg)

        def wrapper(*args, **kwargs):
            signal.signal(signal.SIGALRM, timeout_handler)
            signal.alarm(seconds)
            try:
                ret = func(*args, **kwargs)
            finally:
                signal.alarm(0)
            return ret

        return wraps(func)(wrapper)

    return decorator

class KafkaInterface(object):
    def __init__(self, kafka_url, kafka_zookeeper_port, logger, receive_topic, notify_topic):

        '''
        XXX autocreate topic doesn't work in pykafka, so let's use kafka-python
        to create one.
        '''
        kafka_python_client = kafka_python.KafkaClient(kafka_url)
        kafka_python_client.ensure_topic_exists(receive_topic)
        kafka_python_client.ensure_topic_exists(notify_topic)

        self.logger = logger
        kafka = pykafka.KafkaClient(hosts=kafka_url)
        self.receive_topic_object = kafka.topics[receive_topic]
        self.notify_topic_object = kafka.topics[notify_topic]

        # XXX replace the port in the broker url. This should be passed.
        if kafka_url.find(':') != -1:
            zk_url = kafka_url.rsplit(":", 1)[0] + ":%s" % kafka_zookeeper_port
        else:
            zk_url = kafka_url + ":%s" % kafka_zookeeper_port
        self.consumer = self.receive_topic_object.get_balanced_consumer(
                                 reset_offset_on_start=True,
                                 fetch_message_max_bytes=512*1024*1024,
                                 consumer_group=processor_group,
                                 auto_commit_enable=True,
                                 zookeeper_connect = zk_url)
        self.notifier = self.notify_topic_object.get_producer()

    def next_frame(self):
        while True:
            message = self.consumer.consume()
            if message is not None:
                yield message.value
        
    @timeout(5)
    def notify(self, event="start", namespace="dummy", processor=processor_group, 
               instance_id="unknown", uuid="unknown", text="normal operation"):
    
        timestamp                 = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        timestamp_ms              = int(time.time() * 1e3)
    
        message                   = {}
        message["status"]         = event
        message["timestamp"]      = timestamp
        message["timestamp_ms"]   = timestamp_ms
        message["namespace"]      = namespace
        message["uuid"]           = uuid
        message["processor"]      = processor
        message["instance-id"]    = instance_id
        message["text"]           = text
        
        try:
            self.notifier.produce([json.dumps(message)])
        except Exception, e:
            self.logger.error('Could not send notification to kafka: {0}'.format(e))

@timeout(3600)
def cleanup_local_registry(daemon, mount_pt='/var/lib/docker', min_size=2<<30, target_avail=0.7):
    stat = os.statvfs(mount_pt)
    
    if stat.f_blocks * stat.f_bsize < min_size:
        raise DeviceError(os.strerror(errno.ENOSPC))
    
    if stat.f_bavail * stat.f_bsize < min_size:
        logger.info('Only %d bytes are available in %s. Initiating cleanup' % (stat.f_bavail * stat.f_bsize, mount_pt))
        images = daemon.images()
        images.sort(key=lambda x: x['Created'])
        
        for image in images:
            try:
                daemon.remove_image(image['Id'], force=True)
                logger.info('Removed image %s (tags: %s) from local registry' % (image['Id'], ', '.join(image['RepoTags'])))
            except errors.APIError, e:
                logger.error('Failed to remove image %s: %s' % (image['Id'], str(e)))
            stat = os.statvfs(mount_pt)
            if stat.f_bavail / float(stat.f_blocks) >= target_avail:
                break
        
        logger.info('Volume %s now has %d bytes available' % (mount_pt, stat.f_bavail * stat.f_bsize))

@timeout(60)
def ice_login(registry, user, password, bluemix_api, bluemix_org, bluemix_space):
    registry_user     = ''
    registry_password = ''
    
    registry_host = urlparse.urlparse(registry).netloc
    
    logger.info('ice login --registry %s --user %s --psswd xxxxx --api %s --org %s --space %s' % (registry_host, user, bluemix_api, bluemix_org, bluemix_space))
    proc = subprocess.Popen(["ice", "login",  "--registry", registry_host, "--user", user, "--psswd", password, "--api", bluemix_api, "--org", bluemix_org, "--space", bluemix_space] , stdout=subprocess.PIPE)
    ret = 1
    for line in proc.stdout.readlines():
       if line.find('Login Succeeded') != -1:
           logger.info('Authenticated with container cloud service')
    proc.terminate()
    ret = proc.wait()

    if ret:
        logger.error('Failed to authenticate with container cloud service')
    else:     
        config       = json.load(file(ice_config))
        org_guid     = config['OrganizationFields']['Guid']
        bearer_token = config['AccessToken'].split(' ', 1)[-1]
    
        registry_user = 'bearer'
        registry_password = '%s|%s' % (bearer_token, org_guid)

    return (registry_user, registry_password)

def get_registry_auth(registry, user, password, ice_api, bluemix_api, bluemix_org, bluemix_space):
    registry_user     = None
    registry_password = None
    
    if ice_api:
        try:
            (registry_user, registry_password) = ice_login(registry, user, password, bluemix_api, 
                                                           bluemix_org, bluemix_space)
        except TimeoutError, e:
            logger.error('Ice login timed out: %s' % str(e))
        
    elif user:
        registry_user     = user
        registry_password = password
        
    return (registry_user, registry_password)

@timeout(60)
def registry_login(daemon, registry, user, password, email, ice_api, bluemix_api, bluemix_org, bluemix_space):
    registry_user, registry_password = get_registry_auth(registry, user, password, ice_api, 
                                                         bluemix_api, bluemix_org, bluemix_space)
    
    if not registry_user:
        raise Exception('Failed to authenticate to registry')

    auth = requests.auth.HTTPBasicAuth(registry_user, registry_password)

    registry_version = -1
    ret = requests.request('GET', '%s/v2/' % registry, auth=auth, timeout=http_request_timeout)
    if ret.status_code == requests.codes.ok:
        registry_version = 2
    elif ret.status_code != 404:
        raise RegistryError('Registry version checking failed at %s' % registry)
    else:
        ret = requests.request('GET', '%s/v1/_ping' % registry, auth=auth, 
                           timeout=http_request_timeout)
        if ret.status_code == requests.codes.ok:
            registry_version = 1
        elif ret.status_code != 404:
            raise RegistryError('Registry version checking failed at %s' % registry)

    if registry_version == -1:
        raise RegistryError('Could not find supported registry API at %s' % registry)

    if registry_version == 1:
        daemon.login(
                  username          = registry_user,
                  password          = registry_password,
                  email             = email,
                  registry          = '%s/v1/' % registry
                  )
    elif registry_version == 2:
        daemon.login(
                  username          = registry_user,
                  password          = registry_password,
                  email             = email,
                  registry          = '%s/v2/' % registry
                  )

    return (registry_user, registry_password)

@timeout(1800)
def pull_image(daemon, registry_host, image_name, tag, insecure_registry):
    status = '""'
    logger.info('Pulling image %s/%s:%s (insecure_registry=%s)' % (registry_host, image_name, tag, insecure_registry))
    for status in daemon.pull('%s/%s' % (registry_host, image_name), tag=tag, stream=True, insecure_registry=insecure_registry):
        print status
        
    logger.info(status)
    return status
                 
@timeout(300)
def wait_for_crawler(proc):
    for line in proc.stdout.readlines():
        logger.info(line)
    proc.terminate()
    ret = proc.wait()
    
    return ret

def get_new_image_event(kafka_client):
    for image_event in kafka_client.next_frame():
        try:
            yield json.loads(image_event)
        except json.scanner.JSONDecodeError, e:
            logger.error('Bad data: %s not JSON formatted' % str(image_event))

        
def crawl_images(registry, kafka_host, kafka_zookeeper_port, config_topic, notification_topic, registry_topic, 
                 user, password, email, ice_api, insecure_registry, bluemix_api, 
                 bluemix_org, bluemix_space, instance_id):

    daemon = client.Client(timeout=1800)
    
    if user:
        registry_user, registry_password = registry_login(daemon, registry, user, password, email, 
                                                          ice_api, bluemix_api, bluemix_org, bluemix_space)
    registry_scheme = urlparse.urlparse(registry).scheme
    registry_host = registry[len(registry_scheme)+3:]
    
    while True:
        try:
            cleanup_local_registry(daemon)
            break
        except DeviceError, e:
            logger.error('Docker cache cleanup failed: %s' % str(e))
            return
        except TimeoutError, e:
            logger.error('Docker cache cleanup failed: %s' % str(e))

    kafka_client = KafkaInterface(kafka_host, kafka_zookeeper_port, logger, registry_topic, notification_topic)
    for image_info in get_new_image_event(kafka_client):
        try:
            request_uuid   = image_info['uuid']
        except (KeyError, TypeError):
            request_uuid = str(uuid.uuid1())
            logger.info('Generated uuid=%s for new task on %s.' % (request_uuid, image_info))
            
        try:
            namespace = image_info['namespace']
        except KeyError:
            namespace = 'unknown'
            
        try:
            kafka_client.notify(event="start", namespace=namespace, processor=processor_group, 
                                instance_id=instance_id, uuid=request_uuid)
        except TimeoutError, e:
            logger.error('Kafka notification timed out: %s' % str(e))
            
        try:
            tag            = image_info['tag']
            repository     = image_info['repository']
        
            if namespace == 'unknown':
                namespace = '%s:%s' % (repository, tag)
        
            image_registry, image_name = repository.split('/', 1)
            
            logger.info('Received request %s on namespace %s' % (request_uuid, namespace))
                
            if image_registry != registry_host:
                raise RegistryError('Cannot pull %s:%s from un-authenticated registry' % (repository, tag))
        except (KeyError, ValueError, RegistryError), e:
            logger.error('Bad data: %s' % str(e))
            try:
                kafka_client.notify(event="error", namespace=namespace, processor=processor_group,
                                    instance_id=instance_id, uuid=request_uuid, text='Bad data: %s' % str(e))
            except TimeoutError, e:
                logger.error('Kafka notification timed out: %s' % str(e))
            continue
                    
        image_crawled = False
        for num_tries in range(5):
            try:
                stats = {
                    'pull_time':   0,
                    'pull_count':  0,
                    'crawl_time':  0,
                    'crawl_count': 0,
                    }
                          
                start_time = time.time()
                status = '""'
                try:
                    status = pull_image(daemon, registry_host, image_name, tag, insecure_registry)
                    
                    status = json.loads(status)
                    if 'error' in status:
                        raise RegistryError('Failed to pull image: %s' % status['error'])
                except (TimeoutError, RegistryError), e:
                    logger.error('Image pull failed: %s' % str(e))
                    try:
                        kafka_client.notify(event="error", namespace=namespace, processor=processor_group, 
                                            instance_id=instance_id, uuid=request_uuid, text=str(e))
                    except TimeoutError, e:
                        logger.error('Kafka notification timed out: %s' % str(e))
                    raise e

                stats['pull_time'] += time.time() - start_time
                stats['pull_count'] += 1
                        
                try:
                    kafka_client.notify(event="completed", namespace=namespace, processor=processor_group, 
                                        instance_id=instance_id, uuid=request_uuid)
                except TimeoutError, e:
                    logger.error('Kafka notification timed out: %s' % str(e))
                            
                owner_namespace = image_name.split('/', 1)[0]
                container_name = str(uuid.uuid1())
                    
                start_time = time.time()
                crawl_command = "bash -x /opt/cloudsight/collector/crawler/crawl_docker_image.sh %s %s %s %s %s %s %s %s %s" % \
                                                 (namespace, 
                                                  'kafka://%s/%s' % (kafka_host, config_topic), 
                                                  'kafka://%s/%s' % (kafka_host, notification_topic),
                                                  container_name,
                                                  namespace,
                                                  owner_namespace,
                                                  request_uuid,
                                                  instance_id,
                                                  child_log_file)
                                                  
                logger.info('Invoking crawler: %s' % crawl_command)
                
                ret = -1
                proc = subprocess.Popen(crawl_command, shell=True, stdout=subprocess.PIPE) 
                try:
                    ret = wait_for_crawler(proc)
                except TimeoutError, e:
                    proc.kill()
                    try:
                        ret = wait_for_crawler(proc)
                    except TimeoutError, ex:
                        pass
                    logger.error('Crawler timed out: %s' % str(e))
                    raise e
                            
                stats['crawl_time'] += time.time() - start_time
                if ret == 0:
                    stats['crawl_count'] += 1
                else:
                    raise CrawlerError('Crawler returned error code=%s for image %s:%s' % (str(ret), repository, tag))
                        
                logger.info('Finished processing request %s on namespace %s with stats: %s' % (request_uuid, namespace, json.dumps(stats, sort_keys=True)))
                
                
                image_crawled = True
                break
            except (requests.exceptions.ConnectionError, RegistryError), e:
                logger.info('Registry failure: %s' % str(e))
                if user:
                    try:
                        registry_user, registry_password = registry_login(daemon, registry, user, password, 
                                                                          email, ice_api, bluemix_api, 
                                                                          bluemix_org, bluemix_space)
                    except TimeoutError, e:
                        logger.error('Registry login timed out: %s' % str(e))
            except DeviceError, e:
                logger.critical(str(e))
                raise e
            except Exception, e:
                logger.error(e)
            finally:
                while True:
                    try:
                        cleanup_local_registry(daemon)
                        break
                    except (DeviceError,TimeoutError), e:
                        logger.error('Docker cache cleanup failed: %s' % str(e))
        
        if not image_crawled:
            logger.error('Failed to crawl image %s:%s after 5 attempts.' % (repository, tag))
         
    
if __name__ == '__main__':
    formatter = logging.Formatter('%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s')
    logger = logging.getLogger("regcrawler")
    logger.setLevel(logging.DEBUG)
    
    fh = logging.handlers.RotatingFileHandler(log_file, maxBytes=2<<27, backupCount=4)
    fh.setFormatter(formatter)
    fh.setLevel(logging.INFO)
    logger.addHandler(fh)

    #ch = logging.StreamHandler(sys.stdout)
    #ch.setFormatter(formatter)
    #logger.addHandler(ch)
    
    parser = argparse.ArgumentParser(description="crawl images from docker registry")
    parser.add_argument('registry', type=str, help='container cloud registry, e.g. https://registry-ice.ng.bluemix.net')
    parser.add_argument('kafka_service', type=str, default=None, help='kafka-cs.sl.cloud9.ibm.com:9092')
    parser.add_argument('kafka_zookeeper_port', type=str, default=None, help='kafka zookeeper port')
    parser.add_argument('--ice-api', type=str, default="False", help='use container cloud APIs')
    parser.add_argument('--user', type=str, default=None, help='username')
    parser.add_argument('--password', type=str, default=None, help='password')
    parser.add_argument('--email', type=str, default=None, help='username')
    parser.add_argument('--config-topic', type=str, default='config', help='kafka config topic')
    parser.add_argument('--notification-topic', type=str, default='notification', help='kafka notifications-topic')
    parser.add_argument('--registry-topic', type=str, default='registry-updates', help='kafka registry updates topic')
    parser.add_argument('--insecure-registry', type=str, default="False", help='insecure-registry')
    parser.add_argument('--api-url', type=str, default='https://api.ng.bluemix.net', help='Bluemix API url')
    parser.add_argument('--org', type=str, default=None, help='Bluemix organization')
    parser.add_argument('--space', type=str, default='dev', help='Bluemix space')
    parser.add_argument('--instance-id', type=str, default='unknown', help='regcrawler instance-id')
    
    args = parser.parse_args()
    registry           = args.registry
    kafka_service      = args.kafka_service
    kafka_zookeeper_port = args.kafka_zookeeper_port
    ice_api            = ast.literal_eval(args.ice_api)
    user               = args.user
    password           = args.password
    email              = args.email
    config_topic       = args.config_topic
    notification_topic = args.notification_topic
    registry_topic     = args.registry_topic
    insecure_registry  = ast.literal_eval(args.insecure_registry)
    bluemix_api        = args.api_url
    bluemix_org        = args.org
    bluemix_space      = args.space
    instance_id        = args.instance_id
     
    logger.info('regcrawler.py --ice-api %s --user %s --password xxxx --email %s --config-topic %s --notification-topic %s --registry-topic %s --insecure-registry %s --api-url %s --org %s --space %s --instance-id %s %s %s %s' % \
                               (str(ice_api), user, email, config_topic, notification_topic, registry_topic, str(insecure_registry), bluemix_api, bluemix_org, bluemix_space, instance_id, registry, kafka_service, kafka_zookeeper_port))
    
    if user and not email:
        print >>sys.stderr, "email is required for authentication"
        sys.exit(1) 
        
    if user and not password:
        #print >>sys.stderr, "Enter password for %s:" % user
        #password = sys.stdin.readline().rstrip()
        print >>sys.stderr, "password must be set when user is provided"
        sys.exit(1)
        
    if ice_api and not (user and password):
        print >>sys.stderr, "ice_api requires a user, password, bluemix org and space"
        sys.exit(1)
        
    if ice_api and not bluemix_org:
        bluemix_org = user
        logger.info('Bluemix organization defaulting to %s' % bluemix_org)
        
    crawl_images(registry, kafka_service, kafka_zookeeper_port, config_topic, notification_topic, registry_topic, 
                 user, password, email, ice_api, insecure_registry, bluemix_api, 
                 bluemix_org, bluemix_space, instance_id)
