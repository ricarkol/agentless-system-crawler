#!/usr/bin/env python

'''
This program schedules crawl tasks for new images in a docker registry.

(c) IBM Research 2015
'''

import argparse
import sys
import logging
import logging.handlers
import requests
import time
import subprocess
import uuid
import os
import urlparse
import csv
import datetime
import pykafka
import kafka as kafka_python
from functools import wraps
import errno
import signal
import ast


try:
    import simplejson as json
except:
    import json

log_file = "/var/log/cloudsight/registry-monitor.log"
try:
    ice_config = os.path.join(os.getenv('HOME'), '.cf/config.json')
except AttributeError:
    ice_config = '/.cf/config.json'

class NullHandler(logging.Handler):
    def emit(self, record):
        pass
   
try:
    known_images_file = os.path.join(os.getenv('REGISTRY_DATA'), 'regcrawler_images.csv')
except:
    known_images_file = '/mnt/data/regcrawler/regcrawler_images.csv'

processor_group = 'registry-monitor'
logger              = logging
max_kafka_retries   = 600
http_request_timeout= 120
iterator_sleep_time = 1 * 60 * 60 # 1 hour

class TimeoutError(Exception):
    pass

class RegistryError(Exception):
    pass

class KafkaError(Exception):
    pass


kinterface = None

class KafkaInterface():

    def __init__(self, kafka_url="", publish_topic="registry-updates",
                 receive_topic=None, notification_topic="notification"):

        self.kafka_url = kafka_url
        self.publish_topic = publish_topic
        self.receive_topic = receive_topic
        self.notification_topic = notification_topic

        try_num = 1
        while True:
            try:
                kafka = pykafka.KafkaClient(hosts=kafka_url)
                if publish_topic:
                    self.ensure_topic_exists(publish_topic)
                    self.data_producer = kafka.topics[publish_topic].get_producer()
                if notification_topic:
                    self.ensure_topic_exists(notification_topic)
                    self.notification_producer = kafka.topics[notification_topic].get_producer()
                break
            except Exception, e:
                logger.info('try_num={}, error connecting to {} , reason={}'.format(try_num, kafka_url, str(e)))
                time.sleep(60)
                try_num = try_num + 1


    def ensure_topic_exists(self, topic):
        kafka_python_client = kafka_python.KafkaClient(self.kafka_url)
        kafka_python_client.ensure_topic_exists(topic)
        kafka_python_client.close()


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

def notify(kafka_service, notifications_topic, namespace, uuid, event="start",
           processor="unknown", instance_id="unknown", text="normal operation"):
    
    timestamp                 = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    timestamp_ms              = int(time.time() * 1e3)
    
    message                       = {}
    message["status"]             = event
    message["timestamp"]          = timestamp
    message["timestamp_ms"]       = timestamp_ms
    message['namespace']          = namespace
    message["uuid"]               = uuid
    message["processor"]          = processor
    message["instance-id"]        = instance_id
    message["text"]               = text
   
    try: 
        post_to_kafka(kafka_service, notifications_topic, message)
    except KafkaError, e:
        logger.error(str(e))

@timeout(10)
def send_message(kafka_topic, msg):
    global kinterface
    if kafka_topic == kinterface.notification_topic:
        kinterface.notification_producer.produce([msg])
    elif kafka_topic == kinterface.publish_topic:
        kinterface.data_producer.produce([msg])
    else:
        raise BaseException("unknown topic")

def post_to_kafka(kafka_service, kafka_topic, message):
    msg = json.dumps(message)
    message_posted = False

    for i in range(max_kafka_retries):
        try:
            send_message(kafka_topic, msg)

            message_posted = True
            break
        except TimeoutError, e:
            logger.warn('Kafka send timed out: %s, %s' % (kafka_service, str(message)))
        except Exception, e:
            logger.warn('Kafka send failed: %s, %s (error=%s)' % (kafka_service, msg, str(e)))

        time.sleep(1)

    if not message_posted:
        raise KafkaError('Failed to publish message to Kafka after %d retries: %s' % (max_kafka_retries, msg))
    else:
        logger.debug('published message to Kafka : %s' % ( msg))

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
def registry_login(registry, user, password, email, ice_api, bluemix_api, bluemix_org, bluemix_space):
    registry_user, registry_password = get_registry_auth(registry, user, password, ice_api, 
                                                         bluemix_api, bluemix_org, bluemix_space)
    
    if not registry_user:
        raise Exception('Failed to authenticate to registry')
    
    return (registry_user, registry_password)

def load_known_images():
    known_images = dict()
    
    try:
        with file(known_images_file) as f:
            csv_reader = csv.reader(f, delimiter='\t', quotechar="'")
            for name, tag, id in csv_reader:
                name = json.loads(name)
                if name not in known_images:
                    known_images[name] = dict()
                    known_images[name]['ids'] = []
                    known_images[name]['tags'] = []
                known_images[name]['ids'].append(json.loads(id))
                known_images[name]['tags'].append(json.loads(tag))
            
    except IOError, e:
        logger.warn('Known image cache does not exist at %s' % known_images_file)
        
    logger.info('Loaded metadata for %d images' % len(known_images))
        
    return known_images

def save_known_images(known_images):
    csv.field_size_limit(sys.maxsize) # required to handle large value strings
    
    if len(known_images) == 0:
        return
    
    if not os.path.isdir(os.path.dirname(known_images_file)):
        os.makedirs(os.path.dirname(known_images_file))
    
    with file(known_images_file, 'a') as f:
        csv_writer = csv.writer(f, delimiter='\t', quotechar="'")
        for name, tag, id in known_images:
            csv_writer.writerow((json.dumps(name), json.dumps(tag), json.dumps(id)))
            
    logger.info('Persisted metadata for %d new images' % len(known_images))
    
      
def get_next_image(registry_scheme, registry_host, registry_version, auth, alchemy_registry_api):
    if registry_version == 1:
        return get_next_image_v1(registry_scheme, registry_host, auth)
    elif registry_version == 2:
        return get_next_image_v2(registry_scheme, registry_host, auth, alchemy_registry_api)

def get_next_image_v1(registry_scheme, registry_host, auth):
    registry = '%s://%s' % (registry_scheme, registry_host)
   
    logger.info('Getting list of images in %s' % registry_host) 
    ret = requests.request('GET', '%s/v1/search' % registry, auth=auth, timeout=http_request_timeout)
                                   
    if ret.status_code != requests.codes.ok:
        raise RegistryError('Failed to list images in %s' % registry_host)
                
    images = ret.json()['results']
    logger.info('Received %d image names from registry' % len(images))

    for image in images:
        repository = '%s/%s' % (registry_host, image['name'])
        ret = requests.request('GET', '%s/v1/repositories/%s/tags' % (registry, image['name']), 
                                auth=auth, timeout=http_request_timeout)
                
        if ret.status_code == requests.codes.unauthorized:
            raise RegistryError('Unauthorized to get tags for image %s/%s' % (registry, image['name']))
        elif ret.status_code != requests.codes.ok:
            logger.error('Failed to get tags for image %s/%s: %s' % (registry, image['name'], ret.text))
            continue
                
        tags = ret.json()
                
        for tag, image_id in tags.iteritems():
            image_tag = {
                        'repository': repository,
                        'tag': tag,
                        'id': image_id,
                        'name': image['name']
                        }
            yield image_tag

registry_v2_alchemy_api = False
def get_next_image_v2(registry_scheme, registry_host, auth, alchemy_registry_api):
    registry = '%s://%s' % (registry_scheme, registry_host)
    if registry_v2_alchemy_api:
        logger.info('Getting list of images in %s' % alchemy_registry_api) 
        ret = requests.request('GET', '%s/v1/imageListAll' % alchemy_registry_api, 
                               auth=auth, timeout=http_request_timeout)
                                   
        if ret.status_code != requests.codes.ok:
            raise RegistryError('Failed to list images in %s' % registry_host)

        #images = {"name": "string", "id": "string"}
        images_alchemy = ret.json()
        logger.info('Received %d image names from registry' % len(images_alchemy))
        for image_alchemy in images_alchemy:
            image_name, tag = image_alchemy['name'].rsplit(':')
            repository = '%s/%s' % (registry_host, image_name)
            image_id = image_alchemy['id']

            image = {
                    'repository': repository,
                    'tag': tag,
                    'id': image_id,
                    'name': image_name
                    }
            yield image
    else:
        logger.info('Getting list of images in %s' % registry_host) 
        ret = requests.request('GET', '%s/v2/_catalog' % registry, auth=auth, 
                               timeout=http_request_timeout)
                                   
        if ret.status_code != requests.codes.ok:
            raise RegistryError('Failed to list images in %s' % registry_host)

        image_names = ret.json().get('repositories')
        logger.info('Received %d image names from registry' % len(image_names))

        for image_name in image_names:
            ret = requests.request('GET', '%s/v2/%s/tags/list' % (registry, image_name), 
                                   auth=auth, timeout=http_request_timeout)
            if ret.status_code != requests.codes.ok:
                raise RegistryError('Failed to get tags for image %s/%s' % (registry_host, image_name))

            #{"name":"cloudsight/registry-update","tags":["latest"]}
            tags = ret.json().get('tags')
            for tag in tags:
                ret = requests.request('GET', '%s/v2/%s/manifests/%s' % (registry, image_name, tag), 
                                       auth=auth, timeout=http_request_timeout)
                if ret.status_code != requests.codes.ok:
                    raise RegistryError('Failed to get manifest of iamge %s/%s:%s' % \
                                        (registry_host, image_name, tag))

                digest = ret.headers.get('docker-content-digest')
                if not digest:
                    raise RegistryError('Registry returned no digest header for %s/%s:%s' % \
                                 (registry_host, image_name,tag))

                image = {
                         'repository': '%s/%s' % (registry_host, image_name),
                         'tag': tag,
                         'id': digest,
                         'name': image_name
                         }
                yield image
                 
             
        


def monitor_registry_images(registry, kafka_service, single_run, notification_topic, registry_topic, 
                            user, password, email, ice_api, insecure_registry, bluemix_api, 
                            bluemix_org, bluemix_space, instance_id, alchemy_registry_api):
    global kinterface, registry_v2_alchemy_api
    
    logger.info('Monitoring registry at: %s' % registry)

    kinterface = KafkaInterface(kafka_url=kafka_service)

    logger.info('Created an kafka interface')
    
    if registry.find('://') == -1:
        registry = 'http://%s' % registry
        
    registry_scheme = urlparse.urlparse(registry).scheme
    registry_host = registry[len(registry_scheme)+3:]
    
    auth = {}
    known_images = load_known_images()
    
    if user:
        logger.info('Authenticating user %s with registry %s' % (user, registry))
        registry_user, registry_password = registry_login(registry, user, password, 
                                                          email, ice_api, bluemix_api, 
                                                          bluemix_org, bluemix_space)
        if registry_user:
            auth = requests.auth.HTTPBasicAuth(registry_user, registry_password)
       
    registry_version = -1
    ret = requests.request('GET', '%s/v2/' % registry, auth=auth, timeout=http_request_timeout)
    if ret.status_code == requests.codes.ok:
        logger.info('Using v2 registry')
        registry_version = 2
        if alchemy_registry_api:
            ret = requests.request('GET', '%s/v1/imageListAll' % alchemy_registry_api, 
                                   auth=auth, timeout=http_request_timeout)
            if ret.status_code == requests.codes.ok:
                logger.info('Using alchemy v2 registry endpoint %s' % alchemy_registry_api)
                registry_v2_alchemy_api = True

    elif ret.status_code != 404:
        raise RegistryError('Registry version checking failed at %s' % registry)

    ret = requests.request('GET', '%s/v1/_ping' % registry, auth=auth, 
                           timeout=http_request_timeout)
    if ret.status_code == requests.codes.ok:
        logger.info('Using v1 registry')
        registry_version = 1
    elif ret.status_code != 404:
        raise RegistryError('Registry version checking failed at %s' % registry)

    if registry_version == -1:
        raise RegistryError('Could not find supported registry API at %s' % registry)

 
    iterate = True
    while iterate:
        new_images = []

        try:
            for image in get_next_image(registry_scheme, registry_host, registry_version, auth, alchemy_registry_api):
                repository = image['repository']
                tag        = image['tag']
                image_id   = image['id']
                image_name = image['name']

                if image_name not in known_images:
                    known_images[image_name] = dict()
                    known_images[image_name]['ids'] = []
                    known_images[image_name]['tags'] = []
            
                namespace = '%s:%s' % (repository, tag)
                if tag not in known_images[image_name]['tags'] or image_id not in known_images[image_name]['ids']:
                    logger.info('Discovered new image %s/%s:%s id=%s' % \
                                (registry_host, image_name, tag, image_id))
                        
                    request_uuid = str(uuid.uuid1())

                    notify(kafka_service, notification_topic, namespace, request_uuid, event="start",
                                   processor=processor_group, instance_id=instance_id)
                
                    message = {
                               'repository': repository, 
                               'tag': tag, 
                               'id': image_id, 
                               'uuid': request_uuid, 
                               'namespace': namespace
                              }
                        
                    try:
                        post_to_kafka(kafka_service, registry_topic, message)
                        logger.info("Scheduled processing for image: %s" % str(message))
                    except KafkaError, e:
                        logger.error('Kafka send failure for namespace %s: %s' % (namespace, str(e)))

                        notify(kafka_service, notification_topic, namespace, request_uuid, event="error",
                               processor=processor_group, instance_id=instance_id, text=str(e))
                        continue
                        
                    notify(kafka_service, notification_topic, namespace, request_uuid, event="completed",
                               processor=processor_group, instance_id=instance_id)
                        
                    if image_id not in known_images[image_name]['ids']:
                        known_images[image_name]['ids'].append(image_id)
                    if tag not in known_images[image_name]['tags']:
                        known_images[image_name]['tags'].append(tag)
                            
                    new_images.append((image_name, tag, image_id))
                
                else:
                    logger.info('Image %s/%s:%s (%s) is not new.' % \
                                (registry_host, image_name, tag, image_id))
            
        except (requests.exceptions.ConnectionError, RegistryError), e:
            logger.info('Registry failure: %s' % str(e))
            auth = {}
            if user:
                try:
                    registry_user, registry_password = registry_login(registry, user, password, 
                                                                      email, ice_api, bluemix_api, 
                                                                      bluemix_org, bluemix_space)
                except TimeoutError, e:
                    logger.error('Registry login timed out: %s' % str(e))
            
                if registry_user:
                    auth = requests.auth.HTTPBasicAuth(registry_user, registry_password)
        except Exception, e:
            logger.exception(e)
            
        logger.info('Discovered %d new images' % len(new_images))
        try:
            save_known_images(new_images)
        except (IOError, OSError), e:
            logger.error('Failed to update cache with new images: %s' % str(e))
        
        if single_run:
            iterate = False
        else:
            time.sleep(iterator_sleep_time)
            
    logger.info('Registry monitor is exiting normally') 
                
if __name__ == '__main__':
    log_dir = os.path.dirname(log_file)
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
        os.chmod(log_dir,0755)

    format = '%(asctime)s %(levelname)s %(lineno)s %(funcName)s: %(message)s'
    formatter = logging.Formatter(format)
    
    logger = logging.getLogger("registry-monitor")
    logger.setLevel(logging.DEBUG)
    
    fh = logging.handlers.RotatingFileHandler(log_file, maxBytes=2<<27, backupCount=4)
    fh.setFormatter(formatter)
    fh.setLevel(logging.INFO)
    logger.addHandler(fh)

    h = NullHandler()
    logging.getLogger("kafka").addHandler(h)


    #ch = logging.StreamHandler(sys.stdout)
    #ch.setFormatter(formatter)
    #logger.addHandler(ch)
    #logger.setLevel(logging.DEBUG)
    
    parser = argparse.ArgumentParser(description="monitor docker registry for image updates")
    parser.add_argument('registry', type=str, help='container cloud registry, e.g. https://registry-ice.ng.bluemix.net')
    parser.add_argument('kafka_service', type=str, default=None, help='kafka-cs.sl.cloud9.ibm.com:9092')
    parser.add_argument('--single-run', type=str, default="False", help='run monitor continuously')
    parser.add_argument('--ice-api', type=str, default="False", help='use container cloud APIs')
    parser.add_argument('--user', type=str, default=None, help='username')
    parser.add_argument('--password', type=str, default=None, help='password')
    parser.add_argument('--email', type=str, default=None, help='username')
    parser.add_argument('--notification-topic', type=str, default='notification', help='kafka notifications-topic')
    parser.add_argument('--registry-topic', type=str, default='registry-updates', help='kafka registry updates topic')
    parser.add_argument('--insecure-registry', type=str, default="False", help='insecure-registry')
    parser.add_argument('--api-url', type=str, default='https://api.ng.bluemix.net', help='Bluemix API url')
    parser.add_argument('--org', type=str, default=None, help='Bluemix organization')
    parser.add_argument('--space', type=str, default='dev', help='Bluemix space')
    parser.add_argument('--instance-id', type=str, default='unknown', help='registry-monitor instance-id')
    parser.add_argument('--alchemy-registry-api', type=str, default=None, help='endpoint for alchemy registry v2 API')
    
    args = parser.parse_args()
    registry             = args.registry
    kafka_service        = args.kafka_service
    single_run           = ast.literal_eval(args.single_run)
    ice_api              = ast.literal_eval(args.ice_api)
    user                 = args.user
    password             = args.password
    email                = args.email
    notification_topic   = args.notification_topic
    registry_topic       = args.registry_topic
    insecure_registry    = ast.literal_eval(args.insecure_registry)
    bluemix_api          = args.api_url
    bluemix_org          = args.org
    bluemix_space        = args.space
    instance_id          = args.instance_id
    alchemy_registry_api = args.alchemy_registry_api
     

    if user and not email:
        print >>sys.stderr, "email is required for authentication"
        sys.exit(1) 
        
    if user and not password:
        print >>sys.stderr, "password is required for authentication"
        sys.exit(1)
        
    if ice_api and not (user and password):
        print >>sys.stderr, "ice_api requires a user, password, bluemix org and space"
        sys.exit(1)
        
    if ice_api and not bluemix_org:
        bluemix_org = user
        logger.info('Bluemix organization defaulting to %s' % bluemix_org)
        
    print >>sys.stderr, "starting registry-monitor service"
     
    monitor_registry_images(registry, kafka_service, single_run, notification_topic, 
                            registry_topic, user, password, email, ice_api, 
                            insecure_registry, bluemix_api, bluemix_org, bluemix_space,
                            instance_id, alchemy_registry_api)
    
