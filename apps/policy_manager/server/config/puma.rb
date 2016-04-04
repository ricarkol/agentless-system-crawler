# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
ssl_bind '0.0.0.0', '9292', {
  key: File.expand_path('../ssl.key', __FILE__),
  cert: File.expand_path('../ssl.crt', __FILE__)
}
preload_app!
workers 2
stdout_redirect '/var/log/sentinel/sentinel.log', '/var/log/sentinel/sentinel.log', true
