require "java"
require 'rubygems'
require 'client'

class Logger
  def initialize(*args)
    puts(args)
  end
  def log(*str)
    puts(str)
  end
  def error(*str)
    puts(str)
  end
  def debug(*str)
 #   puts(str[0])
  end
  def info(*str)
  #  puts(str[0])
  end
  def warn(*str)
    puts(str[0])
  end
end

@logger = Logger.new()

mt_prod = {
  :addresses => "logs.opvis.bluemix.net", :port => "9091",
  :window_size => 100, :logger => @logger
}
mt_prod[:tenant_id] = @tenant_id if @tenant_id
mt_prod[:tenant_password] = @tenant_password if @tenant_password 
mt_prod[:supertenant_id] = "Crawler"
mt_prod[:supertenant_password] = "oLYMLA7ogscT"

mt_stage = {
  :addresses => "logs.stage1.opvis.bluemix.net", :port => "9091",
  :window_size => 50, :logger => @logger
}
mt_stage[:tenant_id] = @tenant_id if @tenant_id
mt_stage[:tenant_password] = @tenant_password if @tenant_password 
mt_stage[:supertenant_id] = "Crawler"
mt_stage[:supertenant_password] = "5KilGEQ9qExi"

@client = MTLumberjack::Client.new(mt_prod)

str = (0...100).map { (65 + rand(26)).chr }.join

loop do
  event1 = {
    "message" => "test ricardo 1 " + str,
    "path" => "/var/log/crawler_container_logs/d5c00fbb-90b6-4ace-b69a-0e4e7bd28083/0000/19459c21-e1bd-42f9-a5d3-8808ba250947/test.log",
    #"path" => "/var/log/crawler_container_logs/25aa4c07-4a76-43ba-af53-81af7d1733a9/0000/0cb8e754-3dae-4421-979d-6116f18e65c0/test.log",
  }
  event1['line'] = "test ricardo 1"
  event1['host'] = "prod-dal09-vizio1-host-05"
  event1[MTLumberjack::LB_TIMESTAMP] = Time.now.getutc

  events = Array.new(100) {|i| event1 }
  @client.write_events(events)

  sleep(0.01)
end
