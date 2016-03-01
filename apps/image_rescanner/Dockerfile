FROM ubuntu:trusty
RUN apt-get update --fix-missing
RUN apt-get install -y --fix-missing \
    command-not-found software-properties-common python-software-properties \
    curl wget zip build-essential python-dev python-pip
RUN apt-get install -y --fix-missing openssh-client
RUN pip install elasticsearch elasticsearch-dsl
RUN pip install requests

ADD . /opt/rescanner/

ENTRYPOINT [ "/opt/rescanner/rescan.py" ]
