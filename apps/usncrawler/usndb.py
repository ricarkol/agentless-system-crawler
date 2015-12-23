from __future__ import print_function
import sys
import os
import json
from collections import defaultdict, namedtuple

mydict = defaultdict(list)
USNFix = namedtuple('USNFix', 'usn_major usn_minor pkgver usnid')

def process_usn_info(usn_list):
    for usn_entry in usn_list:
        NameSplit = usn_entry['usnid'].split('-')
        ID1 = NameSplit[1]
        ID2 = NameSplit[2]
        fixdata = usn_entry["fixdata"]  # fixdata is a list
        fixdata_len = len(fixdata)
        for entry in fixdata:   # entry is a dictionary  
            OSVer = entry["distroversion"]  # version of OS
            PkgInfo = entry["packages"] # package information, is a list 
            for entry2 in PkgInfo: # entry2 is a dictionary
                PkgName = entry2["pkgname"] # package name  
                PkgVer = entry2["pkgversion"] # package version
                TupleKey = (OSVer, PkgName)
                mydict[TupleKey].append(USNFix(ID1,ID2,PkgVer, usn_entry['usnid']))  

    for tupleI in mydict:
        itemLen = len(mydict[tupleI])
        if itemLen > 1:
            mydict[tupleI].sort(reverse=True)
    
    for tupleI in mydict:  
        print ('(dist,pkg)={}, fixes={}'.format(tupleI, mydict[tupleI][0].usn_major ))
    
    return mydict

