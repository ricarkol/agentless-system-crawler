FROM python:2.7
WORKDIR /crawler
COPY requirements.txt /crawler/requirements.txt
RUN pip install -v -r requirements.txt
ADD . /crawler
ENTRYPOINT ["python2.7", "crawler.py"]
