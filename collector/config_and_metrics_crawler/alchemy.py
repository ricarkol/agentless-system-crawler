#!/usr/bin/python
# -*- coding: utf-8 -*-

import sys
import os
import subprocess
import traceback
import json
import logging

logger = logging.getLogger('crawlutils')


# Parse the XML description of domU from FNAME
# and return a tuple (name, xmldesc) where NAME
# is the name of the domain, and xmldesc is the contetn of FNAME

#   doc = libxml2.parseDoc(xmldesc)
#   name = doc.xpathNewContext().xpathEval('/domain/name')[0].content

def dump(obj):
    for attr in dir(obj):
        if hasattr(obj, attr):
            print 'obj.%s = %s' % (attr, getattr(obj, attr))


# returns string of path (or None)

def lookup_config_drive_path(domain_name):

    import libvirt
    from libxml2 import parseDoc
    paths = []
    conn = libvirt.open(None)
    if conn is None:

        # print 'Failed to open connection to the hypervisor'

        sys.exit(1)
    try:
        dom = conn.lookupByName(domain_name)
        xml = dom.XMLDesc(0)

        # print "XML obj is:" + str(xml)

        doc = parseDoc(xml)
        disks = doc.xpathNewContext().xpathEval('/domain/devices/disk')
        for disk in disks:

            # dump(disk)

            if disk.prop('device') == 'cdrom':

                # dump(disk)

                for child in disk.get_children():
                    if child.get_name() == 'source':
                        paths.append(child.prop('file'))
        return paths
    except libvirt.libvirtError:
        sys.stdout.flush()
        return paths


metadata_cache = {}


# return None if /openstack/latest/meta_data.json doesn't exist

def get_metadata_json(instance_identifier, type):
    json_data = None
    found = False
    if instance_identifier in metadata_cache:
        return metadata_cache[instance_identifier]

    if type == 'docker':

        # instance_identifier is the full docker id

        if os.path.exists('/openstack/nova/metadata/' +
                          instance_identifier + '.json'):
            logger.debug('Found Nova metadata for %s' %
                         instance_identifier)
            json_data = open('/openstack/nova/metadata/' +
                             instance_identifier + '.json').read()
            found = True
        elif os.path.exists('/var/lib/nova/metadata/' +
                            instance_identifier + '.json'):
            logger.debug('Found Nova metadata for %s' %
                         instance_identifier)
            json_data = open('/var/lib/nova/metadata/' +
                             instance_identifier + '.json').read()
            found = True

    if type == 'kvm':

        # instance_identifier is the libvirt domain-name

        config_drive_paths = \
            lookup_config_drive_path(instance_identifier)
        mountdir = None

        # iterate through each potential config-drive to find metadata until
        # one is found

        for config_drive_path in config_drive_paths:
            if not found:
                try:
                    mountdir = subprocess.Popen(
                        ['/bin/mktemp', '-d'],
                        stdout=subprocess.PIPE).communicate()[0].strip()
                    subprocess.Popen(['mount', '-o', 'loop',
                                      config_drive_path, mountdir],
                                     stdout=subprocess.PIPE).communicate()
                    if os.path.exists(mountdir +
                                      '/openstack/latest/meta_data.json'):
                        json_data = open(mountdir +
                                         '/openstack/latest/meta_data.json'
                                         ).read()
                        found = True
                        logger.debug('Found Nova metadata for %s'
                                     % instance_identifier)
                    subprocess.Popen(['umount', mountdir],
                                     stdout=subprocess.PIPE).communicate()
                    subprocess.Popen(['rmdir', mountdir],
                                     stdout=subprocess.PIPE).communicate()
                except Exception as e:

                    logger.exception(e)
                    traceback.print_exc()
                    if mountdir:
                        subprocess.Popen(['umount', mountdir],
                                         stdout=subprocess.PIPE).communicate()
                        subprocess.Popen(['rmdir', mountdir],
                                         stdout=subprocess.PIPE).communicate()

    if found:
        metadata_cache[instance_identifier] = json_data
    return json_data


def get_namespace(instance_identifier, type):
    metadata = get_metadata_json(instance_identifier, type)

    # The container is not alchemy based XXX The logic of: not crawling if
    # there is no namespace should be more explicit
    if not metadata:
        return None

    try:
        metadata_json = json.loads(metadata)
        tagformat = metadata_json['meta']['tagformat']
        tagseparator = metadata_json['meta']['tagseparator']

        # Issue 123: logmet is not parsing _ correctly
        if tagseparator == '_':
            tagseparator = '.'
    except Exception:
        return None

    namespace = ''
    tag_list = tagformat.split()
    for tag in tag_list:
        if tag != tag_list[0]:
            namespace += tagseparator
        if tag == 'uuid':
            namespace += metadata_json[tag]
        else:
            namespace += metadata_json['meta'][tag]
    return namespace


# XXX if we load the container object with this metadata info, we won't have
# to read it again here.
def get_logs_dir_on_host(instance_identifier, type):
    metadata = get_metadata_json(instance_identifier, type)
    if metadata:
        metadata_json = json.loads(metadata)
        path = ''
    else:
        return '0000/0000/0000'

    try:
        space_id = metadata_json['meta']['space_id']
    except Exception:
        space_id = '0000'

    try:
        path += metadata_json['meta']['tenant_id']
    except Exception:
        path += space_id

    try:
        path += '/'
        path += metadata_json['meta']['group_id']
    except Exception:
        path += '0000'

    try:
        path += '/'
        path += metadata_json['uuid']
    except Exception:
        path += '0000'

    return path
