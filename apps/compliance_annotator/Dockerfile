FROM ubuntu:trusty
RUN apt-get update --fix-missing

RUN apt-get install -y --fix-missing \
    command-not-found software-properties-common python-software-properties \
    curl wget zip build-essential python-dev python-pip

#RUN apt-get install -y --fix-missing supervisor

RUN pip install pytz requests kafka-python elasticsearch elasticsearch-dsl pykafka==1.1.1

#RUN apt-get install -y --fix-missing apache2 openssh-client vim
RUN apt-get install -y --fix-missing openssh-client

ADD ./src /var/www/html/

#COPY startup-services.conf /etc/supervisor/conf.d/startup-services.conf

#EXPOSE 80

ENTRYPOINT [ "/var/www/html/generate_run_script.sh" ]
