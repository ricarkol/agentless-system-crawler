FROM python:2.7
WORKDIR /config_and_metrics_crawler
COPY requirements.txt /config_and_metrics_crawler/requirements.txt
RUN pip install -r requirements.txt
ADD . /config_and_metrics_crawler
ENV DOCKER_VERSION 1.9.1
ADD https://get.docker.com/builds/Linux/x86_64/docker-${DOCKER_VERSION}.tgz /docker.tgz
RUN (cd /; tar xzvf /docker.tgz)
ENTRYPOINT ["python2.7", "crawler.py"]
