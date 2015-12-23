# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require_relative 'support/coverage'
require 'sentinel-docker'

include SentinelDocker::Models

describe SentinelDocker::Models do
  before :all do
    begin
      SentinelDocker::Store.indices.create index: 'testing'
    rescue
      puts 'Index not created. Already existed.'
    end
    SentinelDocker::Config.db.index_name = 'testing'
    @data = {}
    # @container_images = {}
    # @rule_scripts = {}
    @container_images = {
      # "3603892f9519"=>"61afc26cd88e96f8903d11170c61f4004697e46bc7a3f94ef60ec92114c75e85" ,
      # "cc1a225fc739"=>"68ed05e1d9b7cd7429b24eeaac3405d03caa696f4e18259f820505c2aca0f28e" ,
      # "9b8e277ffacb"=>"868be653dea3ff6082b043c0f34b95bb180cc82ab14a18d9d6b8e27b7929762c" ,
      # "e46ebf4351bc"=>"868be653dea3ff6082b043c0f34b95bb180cc82ab14a18d9d6b8e27b7929762c" ,
      # "99b272958373"=>"ecc04d6d638cc9473d1ac0061f1e8575da6e4b6978004a1cfde23ac35862a03b" ,
      "0fcd5456aa35"=>"01375e8d32e457893028dee10093c1c4335116b4c05e3600e6561c17c2ce0f67" ,
      "493461cc7474"=>"0beee7f478c860c8444aa6a3966e1cb0cd574a01c874fc5dcc48585bd45dba52" ,
      "f9927a2a821e"=>"2cea2911ebcb7f1bb6fb3cadcc8805aaa9df07fba84e7f7f8f5dac0744dada60"
    }

    @rule_scripts = [
      'Rule.authentication.pass_max_days.py',
      'Rule.authentication.pass_min_len.py',
      'Rule.authentication.pass_min_days.py',
      'Rule.authentication.remember_parameter_of_pam_unix_so.py',
      'Rule.service_integrity.systematic_logon_attacks.py',
      'Rule.business_use_notice.motd.py'
    ]

  end

  # @container_images = {
  #   "container1" => "image1",
  #   "container2" => "image2"
  # }


  it 'namespace query' do
    containers = {}
    images = {}

    current_time = Time.now
    max_days=30 #days
    interval=10 #days
    begin_time = (current_time-max_days*24*60*60)
    end_time = begin_time+interval*24*60*60

    begin_time.utc
    end_time.utc

    until current_time - begin_time < 0

      puts "searching namespaces from #{begin_time.iso8601} to #{end_time.iso8601}"
      namespaces = SentinelDocker::CloudsightUtil.get_namespaces(begin_time, end_time)
      new_containers = {}
      new_images = {}
      namespaces.each do |ns|
        next if containers.has_key?(ns) || images.has_key?(ns)   #check if it exists in s&c database
        if md = ns.match(/regcrawl-image-([0-9a-f]+)\/([0-9a-f]+)/)
          crawl_times = SentinelDocker::CloudsightUtil.crawl_times(ns, begin_time, end_time)
          new_containers[ns] = {
            image_id: md[1],
            container_id: md[2],
            crawl_times: crawl_times
          }
        elsif md = ns.match(/regcrawl-image-([0-9a-f]+)/)
          crawl_times = SentinelDocker::CloudsightUtil.crawl_times(ns, begin_time, end_time)
          new_images[ns] = {
            image_id: md[1],
            crawl_times: crawl_times
          }
        else
          next
        end

      end
      puts "  ==> new containers: #{JSON.pretty_generate(new_containers)}"
      puts "  ==> new images: #{JSON.pretty_generate(new_images)}"

      #create image
      #create container

      #trigger exec rule scripts
      #get result from ES

      containers.merge!(new_containers)
      images.merge!(new_images)

      containers.each do |ns, map|
        results = SentinelDocker::CloudsightUtil.get_results(ns, map[:container_id], begin_time, end_time)
        unless results.empty?
          puts "  ==> new results for container <#{ns}> : "
          puts "      #{JSON.pretty_generate(results)} "
        end
      end

      images.each do |ns, map|
        results = SentinelDocker::CloudsightUtil.get_results(ns, map[:image_id], begin_time, end_time)
        unless results.empty?
          puts "  ==> new results for image <#{ns}> : "
          puts "      #{JSON.pretty_generate(results)} "
        end
      end

      begin_time = end_time
      end_time = begin_time+interval*24*60*60

      puts "changed begin: #{begin_time.iso8601}, end: #{end_time.iso8601}"
    end

  end


  after :all do
    SentinelDocker::Store.indices.delete index: 'testing'
  end

end
