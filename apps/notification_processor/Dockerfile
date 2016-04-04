FROM ubuntu:trusty
RUN apt-get update --fix-missing

RUN apt-get install -y --fix-missing \
    command-not-found software-properties-common python-software-properties \
    curl wget zip python-dev python-pip

RUN pip install pytz requests kafka-python elasticsearch elasticsearch-dsl pykafka==1.1.1
ADD . /opt/notification_processor
ENTRYPOINT [ "/opt/notification_processor/src/notification_processor.py" ]
