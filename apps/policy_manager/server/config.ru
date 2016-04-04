# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
# Run this file with `rackup`
#require 'sentinel'
require 'sentinel-docker'
#require 'sentinel/rack/doorman'
require 'sentinel-docker/rack/doorman'
require 'rack/session/cookie'

#use Rack::CommonLogger, Sentinel::Log.instance_eval { @logdev }
use Rack::CommonLogger, SentinelDocker::Log.instance_eval { @logdev }

use Rack::Session::Cookie, secret: '2KXL7iKldwfojOAT', expire_after: 14400 # 4 hours
#use Sentinel::Rack::Doorman
use SentinelDocker::Rack::Doorman

map '/coverage' do
  run Rack::Directory.new(File.expand_path('../coverage', __FILE__))
end

map '/web' do
  run Rack::Directory.new(File.expand_path('../public', __FILE__))
end


#run Sentinel::API::Root
run SentinelDocker::API::Root
