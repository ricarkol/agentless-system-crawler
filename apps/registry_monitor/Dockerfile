FROM ubuntu:trusty
MAINTAINER Nilton Bila <nilton@us.ibm.com>

WORKDIR /vagrant/apps/registry_monitor
RUN apt-get update --fix-missing
RUN apt-get install -y --fix-missing python-pip
RUN pip install simplejson pykafka==1.1.1 kafka-python
ADD registry_monitor.py /vagrant/apps/registry_monitor/
RUN chmod u+x registry_monitor.py
ENTRYPOINT [ "./registry_monitor.py"]
