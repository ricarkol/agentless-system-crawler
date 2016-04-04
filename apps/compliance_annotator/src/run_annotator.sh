#!/bin/bash

./compliance_scanner.py --kafka-url demo3.sl.cloud9.ibm.com:9092 --receive-topic config --annotation-topic compliance --notification-topic notification --elasticsearch-url demo3.sl.cloud9.ibm.com:9200 --annotator-home /var/www/html
