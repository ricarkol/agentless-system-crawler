from setuptools import setup, find_packages
import codecs
import os

here = os.path.abspath(os.path.dirname(__file__))

# Read the version number from a source file.
# Why read it, and not import?
# see https://groups.google.com/d/topic/pypa-dev/0PkjVpcxTzQ/discussion
def find_version(*file_paths):
    # Open in Latin-1 so that we avoid encoding errors.
    # Use codecs.open for Python 2 compatibility
    with codecs.open(os.path.join(here, *file_paths)) as f:
        version = f.read()
        return str(version.rstrip('\r\n'))
    raise RuntimeError("Unable to find version string.")


# Get the long description from the relevant file
with codecs.open('DESCRIPTION.rst', encoding='utf-8') as f:
    long_description = f.read()
    
setup(
    name="cloudsight-kelk-search",
    version=find_version('VERSION'),
    description="CloudSight Elasticsearch Search Service",
    long_description=long_description,

    # The project URL.
    #url='',

    # Author details
    # author='',
    # author_email='',

    # Choose your license
    # license='MIT',

    classifiers=[
        # How mature is this project? Common values are
        #   3 - Alpha
        #   4 - Beta
        #   5 - Production/Stable
        'Development Status :: 3 - Alpha',

        # Indicate who your project is intended for
        'Intended Audience :: DevOps Analytics Users',
        'Topic :: DevOps Analytics :: Problem Determination Tools',

        # Pick your license as you wish (should match "license" above)
        # 'License :: OSI Approved :: MIT License',

        # Specify the Python versions you support here. In particular, ensure
        # that you indicate whether you support Python 2, Python 3 or both.
        # TODO: test in other Python versions
        'Programming Language :: Python :: 2.7',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.1',
        'Programming Language :: Python :: 3.2',
        'Programming Language :: Python :: 3.3',
    ],

    # What does your project relate to?
    keywords='DevOps Analytics problem determination',
    
    # Find the packages in the dir 'src'
    #package_dir = {'': '.'},

    # You can just specify the packages manually here if your project is
    # simple. Or you can use find_packages.
    packages = find_packages(exclude=["*.tests", "*.tests.*", "tests.*", "tests"]),

    # List run-time dependencies here.  These will be installed by pip when your
    # project is installed.
    install_requires = ['elasticsearch==1.3.0', 'flask==0.10.1', 'python-dateutil==2.2', 'argparse==1.2.1', 'prettytable==0.7.2', 'pytz==2013.9'],

    # If there are data files included in your packages that need to be
    # installed, specify them here.  If using Python 2.6 or less, then these
    # have to be included in MANIFEST.in as well.
    package_data={
        'search.static': ['css/*', 'js/*', 'fonts/*', '*.gif'],
        'search': ['templates/*'],
    },

    # Specify data files to place that are outside of the packages.
    # see http://docs.python.org/3.4/distutils/setupscript.html#installing-additional-files
    # The first entry in each tuple is the location where the file will be copied. It is relative
    # to the Python installation directory (sys.prefix, or sys.exec_prefix). If it is given as
    # an empty string, it will be the top level of the Python installation directory. 
    #data_files = [(static_target_dir, static_files), (template_target_dir, template_files)],
     
    scripts = [
     'bin/search'
    ]

    # To provide executable scripts, use entry points in preference to the
    # "scripts" keyword. Entry points provide cross-platform support and allow
    # pip to create the appropriate form of executable for the target platform.
    #entry_points={
    #    'console_scripts': [
    #        'search=search.cli.search_cli:main',
    #    ],
    #},
)
