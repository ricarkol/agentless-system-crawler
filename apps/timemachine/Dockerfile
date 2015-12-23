FROM ubuntu:trusty

MAINTAINER sastry Duri <sastry@us.ibm.com>

ENV TIMEMACHINE_PORT 8600
ENV TIMEMACHINE_VERSION 0.1.0

RUN apt-get update --fix-missing

RUN apt-get install -y --fix-missing \
    command-not-found software-properties-common python-software-properties \
    curl wget zip python-dev python-pip

#RUN pip install pytz requests kafka-python elasticsearch elasticsearch-dsl pykafka

RUN pip install requests simplejson pytz pydoubles flask prettytable python-dateutil elasticsearch elasticsearch-dsl
ADD . /opt/timemachine

EXPOSE 8600

ENTRYPOINT [ "/opt/timemachine/timemachine" ]
