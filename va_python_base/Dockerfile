FROM ubuntu:14.04
RUN apt-get update

RUN apt-get install -y --fix-missing \
    john pkg-config libreadline-dev libxml2-dev python-dev python-pip wget

# If we neglect to transfer something from the requirements file... It doesn't really matter.
# These are basically here as an efficiency saving.
RUN pip install pytz requests==2.4.3 kafka-python pykafka==2.3.0

ADD . ./install/va_python_base/

RUN mv ./install/va_python_base/setup.py ./install/

RUN echo "reinstalling va_python_base" && pip install ./install/

RUN rm -rf ./install

ADD ./sanitize_files.py ./

RUN python sanitize_files.py