FROM ubuntu:trusty
MAINTAINER Nilton Bila <nilton@us.ibm.com>

WORKDIR /vagrant/apps/registry_update
RUN apt-get update --fix-missing
RUN apt-get install -y --fix-missing python-pip
RUN pip install simplejson flask pykafka==1.1.1 kafka-python

ADD registry_update.py /vagrant/apps/registry_update/
RUN chmod u+x registry_update.py

ENTRYPOINT [ "./registry_update.py"]
