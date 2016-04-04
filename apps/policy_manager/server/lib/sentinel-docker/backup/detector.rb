#!/bin/ruby
# coding: utf-8
# 
# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'sentinel-docker'
require 'sentinel-docker/docker_util'

include SentinelDocker::Models

begin
  SentinelDocker::Store.indices.create index: 'testing'
rescue
  puts 'Index not created. Already existed.'
end
SentinelDocker::Config.db.index_name = 'testing'

#require 'sentinel-docker/models'

# load_crawled_data (periodically executed)
start_time = Time.now
max_days=45 #days
interval_before_start=15*24*60*60
interval_for_latest = 120
buffer_time = 10
begin_time = (start_time-max_days*24*60*60)
end_time = begin_time+interval_before_start

begin_time.utc
end_time.utc

loop do

  need_update = false
  need_update = true if SentinelDocker::DockerUtil.sync_server_state(begin_time, end_time)
  need_update = true if SentinelDocker::DockerUtil.trigger_selected_rules

  begin_time = end_time
  if end_time < start_time 
    end_time = [start_time, begin_time+interval_before_start].min
  else
    end_time = end_time+interval_for_latest
  end
  begin_time.utc
  end_time.utc

  puts "changed range from #{begin_time.iso8601} to #{end_time.iso8601}"

  if need_update
    puts "update status report"
    SentinelDocker::DockerUtil.create_status_report
  end

  secs = end_time - Time.now + buffer_time
  if secs > 0
    puts "waiting #{secs} seconds"
    sleep(secs)
  end

  begin_time -= buffer_time   

end

#show_report


# finalize
#SentinelDocker::Store.indices.delete index: 'testing'

# end of script


