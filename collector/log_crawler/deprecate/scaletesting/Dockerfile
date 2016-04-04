FROM cloudsight/logcrawler
RUN pip install jinja2
ADD . /vagrant/collector/log_crawler/scaletesting/
ENTRYPOINT [ "/vagrant/collector/log_crawler/scaletesting/start-in-docker.py" ]
CMD [ "--help" ]
