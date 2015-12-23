FROM cloudsight/kelk-base

ENV SEARCH_SERVICE_PORT 8885
ENV SEARCH_SERVICE_VERSION 0.1.0
ENV SEARCH_SERVICE_PKG_NAME cloudsight-kelk-search

# Copy the Search Service Python package
RUN mkdir -p /opt/$SEARCH_SERVICE_PKG_NAME
COPY dist/$SEARCH_SERVICE_PKG_NAME-$SEARCH_SERVICE_VERSION.tar.gz/ /opt/$SEARCH_SERVICE_PKG_NAME/$SEARCH_SERVICE_PKG_NAME-$SEARCH_SERVICE_VERSION.tar.gz
COPY start-search-service-in-docker.sh /opt/$SEARCH_SERVICE_PKG_NAME/start-search-service-in-docker.sh

# Install the Search Service
RUN pip install /opt/$SEARCH_SERVICE_PKG_NAME/$SEARCH_SERVICE_PKG_NAME-$SEARCH_SERVICE_VERSION.tar.gz

# Configure supervisord
COPY startup-services.conf /etc/supervisor/conf.d/startup-services.conf

EXPOSE $SEARCH_SERVICE_PORT
