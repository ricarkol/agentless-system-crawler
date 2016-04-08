FROM ubuntu:trusty
RUN apt-get update --fix-missing
RUN apt-get install -y --fix-missing \
    command-not-found software-properties-common python-software-properties \
    curl wget zip build-essential python-dev python-pip yum
RUN pip install pytz requests kafka-python elasticsearch elasticsearch-dsl pykafka==1.1.1
ADD . /opt/compliance_annotator/
ENTRYPOINT [ "/opt/compliance_annotator/compliance_scanner.py" ]
