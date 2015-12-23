FROM ubuntu:14.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y install supervisor openjdk-7-jdk vim python-pip wget

CMD ["/usr/bin/supervisord","-n"]
