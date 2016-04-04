#Comment out next line and uncomment the following for protobuf support
FROM ubuntu:trusty 
#FROM cloudsight/base-proto

ADD . /vagrant/apps/ping_worker
WORKDIR /vagrant/apps/ping_worker
RUN apt-get update --fix-missing
RUN apt-get -y install --fix-missing pkg-config libreadline-dev libxml2-dev python-pip wget
RUN pip install requests simplejson pytz pydoubles kafka-python pykafka

ENV LD_LIBRARY_PATH lib
ENV LIBRARY_PATH lib
ENTRYPOINT [ "./ping.py"]
