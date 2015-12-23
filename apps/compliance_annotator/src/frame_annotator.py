#!/usr/bin/env python2.7

from __future__ import print_function
import os
import sys
import json
import logging

DIRNAME = os.path.abspath(os.path.dirname(__file__))
USNFILE = os.path.join(DIRNAME, 'usninfos.json')
USNINFOS = json.loads(open(USNFILE, 'r').read())

class cached_property(object):
    """
    Decorator that converts a method with a single self argument into a
    property cached on the instance.
    """
    def __init__(self, func):
        self.func = func

    def __get__(self, instance, type=None):
        if instance is None:
            return self
        res = instance.__dict__[self.func.__name__] = self.func(instance)
        return res

class MakeScan(object):

    DISTRO_CHOICES = [ 'saucy', 'quantal', 'precise', 'lucid', 'trusty', 'utopic', ]

    def get_distro(self, osinfo, namespace):
        if not osinfo:
            logging.error('No OS information found for namespace:{}, osinfo={}'.format(namespace, json.dumps(osinfo)))
            return None
        try:
            osname = osinfo['osname']
        except:
            logging.error('No osname field found for namespace:{}, osinfo={}'.format(namespace, json.dumps(osinfo)))
            return None

        for d in self.DISTRO_CHOICES:
            if d in osname:
                return d
        logging.warning('Probably not a Ubuntu machine namespace:{}, osinfo={}'.format(namespace, json.dumps(osinfo)))
        return None

    def get_usn_fix_packages(self, distro, usnid, usninfo):
        """
        The packages and versions that fix the USN on this distro.
        """
        try:
            for fd in usninfo['fixdata']:
                if fd['distroversion'] == distro:
                    return fd['packages']
        except:
            logging.error('Could not parse usninfo for usnid: {}'.format(usnid))
            return None

        logging.warning('No USN info match found for usnid {} in distro {}'.format(usnid, distro))
        return None

    def scanNamespaceForUsn(self, namespace, timestamp, distro, packages, usnid, usninfo, vulnerabilities):
        fixes = self.get_usn_fix_packages(distro, usnid, usninfo)
        if not fixes:
            return
        vulnerable = any(((f['pkgname'] in packages) and (f['pkgversion'] != packages[f['pkgname']]))for f in fixes)
        vulnerable_package = {}
        if vulnerable:
             for f in fixes:
                 pkgname = f['pkgname']
                 try:
                     pkgversion = packages[pkgname]
                     vulnerable_package[pkgname] = pkgversion
                 except KeyError, e:
                     logging.warning('fix package:{} not applicable for namespace:{}'.format(pkgname, namespace))

        vulnerability_annotation = {
            'namespace': namespace,
            'timestamp': timestamp,
            'usnid': usnid,
            'summary':usninfo.get('summary', 'Could not find summary'),
            'vulnerable': vulnerable
        }

        if vulnerable:
            vulnerability_annotation['fixes'] = fixes
            vulnerability_annotation['distro'] = distro
            vulnerability_annotation['vulnerable_package'] = vulnerable_package

        vulnerabilities.append(vulnerability_annotation)
        return vulnerable

    def makeScanForNamespace(self, namespace, timestamp, osinfo, packages):
        vulnerabilities = []
        distro = self.get_distro(osinfo, namespace)
        if not distro:
            return
        if not packages:
            return
        packages = {
            p['pkgname']: p['pkgversion'] for p in packages
        }

        vulnerability_count = 0
        for usninfo in USNINFOS:
            usnid = usninfo['usnid']
            vulnerable = self.scanNamespaceForUsn(namespace, timestamp, distro, packages, usnid, usninfo, vulnerabilities)
            if vulnerable:
                 vulnerability_count =  vulnerability_count + 1
        logging.info('namespace:{}, usn checked={}, vulnerabilities={}'.format(namespace, len(USNINFOS), vulnerability_count))
        return vulnerabilities

