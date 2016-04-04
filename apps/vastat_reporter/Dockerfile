FROM ubuntu:trusty
RUN apt-get update --fix-missing

RUN apt-get install -y --fix-missing \
    command-not-found software-properties-common python-software-properties \
    curl wget zip build-essential python-dev python-pip

RUN pip install elasticsearch elasticsearch-dsl

RUN pip install pytz requests kafka-python pykafka
RUN apt-get install -y --fix-missing openssh-client

ADD . /opt/vastat/

ENTRYPOINT [ "/opt/vastat/report_kpi.py" ]
