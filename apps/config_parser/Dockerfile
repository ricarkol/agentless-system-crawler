#Comment out next line and uncomment the following for protobuf support
FROM alchemyregistry.hursley.ibm.com:5000/va_python_base:latest
MAINTAINER Peter Meckiffe <pmeckif1@uk.ibm.com>

ADD . /vagrant/apps/config_parser
WORKDIR /vagrant/apps/config_parser
RUN apt-get update
RUN apt-get -y install --fix-missing pkg-config libreadline-dev libxml2-dev python-dev python-pip wget
RUN pip install pydoubles
RUN make
ENV LD_LIBRARY_PATH lib
ENV LIBRARY_PATH lib
RUN python test_config_parser.py
ENTRYPOINT [ "./config_parser.py"]
CMD [ "--help" ]
