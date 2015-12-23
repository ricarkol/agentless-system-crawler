#Comment out next line and uncomment the following for protobuf support
FROM ubuntu:trusty 
#FROM cloudsight/base-proto
MAINTAINER Nilton Bila <nilton@us.ibm.com>

ADD . /vagrant/apps/config_parser
WORKDIR /vagrant/apps/config_parser
RUN apt-get update --fix-missing
RUN apt-get -y install --fix-missing pkg-config libreadline-dev libxml2-dev python-pip wget
RUN pip install requests simplejson pytz pydoubles kafka-python pykafka==1.1.1
RUN make
ENV LD_LIBRARY_PATH lib
ENV LIBRARY_PATH lib
RUN python test_config_parser.py
ENTRYPOINT [ "./config_parser.py"]
CMD [ "--help" ]
