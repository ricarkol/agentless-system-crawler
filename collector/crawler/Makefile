SHELL := /bin/bash

all: prereqs

prereqs: FORCE
	if [ -e "/usr/bin/apt-get" ]; then \
		echo "Using apt-get to install pre-reqs"; \
		sudo apt-get install -y python-pip gcc python-dev; \
		sudo apt-get install -y rpm; \
  	elif [ -e "/usr/bin/yum" ]; then \
		echo "Using yum to install pre-reqs"; \
		sudo yum install -y python-pip gcc python-devel; \
		# sudo yum install dpkg; \
  	fi
	#sudo easy_install psutil simplejson bottle requests
	#sudo pip install psutil bottle requests simplejson pydoubles netifaces kafka-python docker-py
	sudo pip install --no-index --find-links="../../packaging/python_packages/" psutil bottle requests simplejson pydoubles netifaces kafka-python docker-py pykafka

executable: prereqs pyinstaller crawler.spec python-setuptools
	python pyinstaller-2.0/pyinstaller.py --onefile crawler.spec
	echo 'Successfully built executable: crawler'

python-setuptools:
	if [ -e "/usr/bin/apt-get" ]; then \
		echo "Using apt-get to install python-setuptools"; \
		sudo apt-get install -y python-setuptools; \
  	elif [ -e "/usr/bin/yum" ]; then \
		echo "Using yum to install python-setuptools"; \
		sudo yum install -y python-setuptools; \
  	fi

pyinstaller:
	if [ ! -e "pyinstaller-2.0.tar.bz2" ]; then \
		wget -O pyinstaller-2.0.tar.bz2 http://sourceforge.net/projects/pyinstaller/files/2.0/pyinstaller-2.0.tar.bz2/download; \
	fi
	tar jxvf pyinstaller-2.0.tar.bz2


FORCE:

