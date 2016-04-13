#! /usr/bin/python
from setuptools import setup, find_packages
from setuptools.command.install import install
from subprocess import check_call


class InstallCommand(install):
    # Build the translation binaries before doing the rest of the install.
    def run(self):
        install.run(self)

setup(
    name='va_python_base',
    version='0.0.1',
    packages=find_packages(exclude=["tests", "tests.*"]),
    description='A common library of functions for all of the '
                'VA micro-services',
    author='IBM VA Developers',
    url='https://github.ibm.com/alchemy-va/CloudSight',
    install_requires=[
        'pytz',
        'requests==2.4.3',
        'kafka-python',
        'pykafka==2.3.0'
    ],
    cmdclass={'install': InstallCommand})