FROM cloudsight/base
RUN pip install pytz requests kafka-python
ADD . /opt/vulnerability_annotator
ENTRYPOINT [ "/opt/vulnerability_annotator/vulnerability_annotator.py" ]
CMD [ "--help" ]
