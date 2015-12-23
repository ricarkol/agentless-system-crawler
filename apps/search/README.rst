KELK-based CloudSight Search Service 
====================================

This README file provides some basic information about testing and running the Elasticsearch-based Search Service.

1 - Information for developers
------------------------------

Dependencies
~~~~~~~~~~~~

This service is written in Python. In order to run all unit tests, you need to install:

  * VirtualBox and Vagrant

  * nose

You can find documentation online on how to configure VirtualBox and Vagrant for your operating
system.

You can install *nose* by simply running: ``pip install nose``

In addition, PDaaS depends on a few Python packages available on PyPI (https://pypi.python.org/pypi),
namely::

  +------------------ +-------------------------------------+
  |Python Package     |        License                      |
  +===================+=====================================+
  | elasticsearch     | Apache License, Version 2.0         |
  +-------------------+-------------------------------------+
  | flask             | BSD license                         |
  +-------------------+-------------------------------------+
  | python-dateutil   | Simplified BSD                      |
  +-------------------+-------------------------------------+
  | pytz              | MIT                                 |
  +-------------------+-------------------------------------+
  | argparse          | Python Software Foundation License  |
  +-------------------+-------------------------------------+
  | prettytable       | New BSD License                     |
  +-------------------+-------------------------------------+
  

Building the Python package
~~~~~~~~~~~~~~~~~~~~~~~~~~~

To build the Search service Python package, run the script  ``build.sh``.
It will create the package file under the ``dist`` directory.


Running the unit tests
~~~~~~~~~~~~~~~~~~~~~~

Follow these steps to run all unit tests:

  1. cd into the vagrant directory

  2. run: ``vagrant up``. Note that this step will take a long time, since it will download the test data to populate the local Elasticsearch. The unit tests rely on this data.

  3. cd into the top directory of the search service directory tree

  4. run: ``nosetests -v``

To run the unit tests in verbose mode, you can add the option ``--nocapture`` to the ``nosetests`` command.


2 - Running the Search Service
------------------------------

More to be added...
