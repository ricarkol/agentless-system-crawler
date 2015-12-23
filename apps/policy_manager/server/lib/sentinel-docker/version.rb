# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
module SentinelDocker
  last_rev_path = File.expand_path('../../../.last_rev', __FILE__)
  VERSION = '1.0.0'
  REVISION = File.exists?(last_rev_path) ? IO.read(last_rev_path) : 'dev'
  CHEF_VERSION = '11.16.4'
end
