FROM alchemyregistry.hursley.ibm.com:5000/va_python_base:latest
RUN apt-get update --fix-missing

RUN apt-get install -y --fix-missing \
    python-pip john

RUN pip install pytz requests kafka-python pykafka==2.3.0

ADD ./src /opt/cloudsight/apps/password_annotator

ENTRYPOINT [ "/opt/cloudsight/apps/password_annotator/password_annotator.py" ]
