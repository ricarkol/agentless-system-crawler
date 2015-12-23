AUGEAS_ROOT := $(shell pwd)
DOWNLOADS_DIR := ./downloads

install: prereqs augeas python-augeas lenses

prereqs:
	mkdir -p $(DOWNLOADS_DIR)
#	@easy_install pip

augeas:
	if [ ! -f ${AUGEAS_ROOT}/bin/augtool ]; then \
		if [ ! -f ${DOWNLOADS_DIR}/augeas-1.3.0.tar.gz ]; then \
			wget -O ${DOWNLOADS_DIR}/augeas-1.3.0.tar.gz --no-check-certificate http://download.augeas.net/augeas-1.3.0.tar.gz; \
		fi;\
		if [ ! -d ${DOWNLOADS_DIR}/augeas-1.3.0 ]; then\
			(cd ${DOWNLOADS_DIR};  tar -xzf augeas-1.3.0.tar.gz;); \
		fi;\
		(cd ${DOWNLOADS_DIR}/augeas-1.3.0 && ./configure --prefix=$(AUGEAS_ROOT) && make  &&  make install;); \
	fi

python-augeas:
	if [ -z `pip freeze | grep augeas` ]; then \
		if [ ! -f ${DOWNLOADS_DIR}/python-augeas-0.5.0.tar.gz ]; then \
			wget -O ${DOWNLOADS_DIR}/python-augeas-0.5.0.tar.gz --no-check-certificate https://fedorahosted.org/released/python-augeas/python-augeas-0.5.0.tar.gz;\
		fi;\
		if [ ! -d ${DOWNLOADS_DIR}/python-augeas-0.5.0 ]; then\
			(cd ${DOWNLOADS_DIR}; tar -xzf python-augeas-0.5.0.tar.gz;)\
		fi;\
		(cd ${DOWNLOADS_DIR}/python-augeas-0.5.0 && export prefix=$(AUGEAS_ROOT) && python setup.py install;);\
	fi

lenses:
	cp lenses/* $(AUGEAS_ROOT)/share/augeas/lenses/dist/

clean:
	cd ${DOWNLOADS_DIR}/augeas-1.3.0 && make distclean
