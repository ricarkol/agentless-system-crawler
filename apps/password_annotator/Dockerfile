FROM ubuntu:14.04
RUN apt-get update --fix-missing

RUN apt-get install -y --fix-missing \
    python-pip john

RUN pip install simplejson pytz requests kafka-python pykafka==1.1.1

ADD ./src /opt/cloudsight/apps/password_annotator

ENTRYPOINT [ "/opt/cloudsight/apps/password_annotator/password_annotator.py" ]
