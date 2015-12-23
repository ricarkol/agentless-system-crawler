FROM cloudsight/base
RUN pip install pyyaml
ADD logstash-1.4.0.tar.gz /opt
RUN ln -svf /opt/logstash-1.4.0 /opt/logstash
ADD Tenjin-1.1.1.tar.gz /tmp/
RUN cd /tmp/Tenjin-1.1.1 && python setup.py install
ADD conf /vagrant/collector/log_crawler/conf
ADD start.sh /vagrant/collector/log_crawler/start.sh
ADD config_shipper.py /vagrant/collector/log_crawler/config_shipper.py
ADD log_crawler_config.py /vagrant/collector/log_crawler/log_crawler_config.py
ADD logstash /vagrant/collector/log_crawler/logstash
