FROM alchemyregistry.hursley.ibm.com:5000/va_python_base:latest
RUN apt-get update --fix-missing
RUN apt-get install -y --fix-missing \
    command-not-found software-properties-common python-software-properties \
    curl wget zip build-essential python-dev python-pip yum
RUN pip install pytz requests elasticsearch elasticsearch-dsl
ADD . /opt/compliance_annotator/
ENTRYPOINT [ "/opt/compliance_annotator/compliance_scanner.py" ]
