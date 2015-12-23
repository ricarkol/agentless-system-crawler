FROM ubuntu:trusty
RUN apt-get update --fix-missing

RUN apt-get install -y --fix-missing \
    command-not-found software-properties-common python-software-properties \
    curl wget zip python-dev python-pip yum

RUN pip install pytz requests simplejson kafka-python elasticsearch elasticsearch-dsl beautifulsoup4==4.3.2
ADD . /opt/usncrawler

WORKDIR /opt/usncrawler
ENTRYPOINT [ "/opt/usncrawler/security_crawler.py" ]
