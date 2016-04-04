require 'sentinel-docker'
require 'sentinel-docker/docker_util'
require 'sentinel-docker/rule_runner'
require 'sentinel-docker/esutil'
require 'parallel'
# require 'profiler'

# RubyVM::InstructionSequence.compile_option = {
#   :trace_instruction => true,
#   :specialized_instruction => false
# }

#Profiler__::start_profile

#Log = SentinelDocker::Log

module SentinelDocker
  module SCServerControl

    Log = SentinelDocker::Log
    #Log = Logger.new(STDOUT)
    Log.level = Logger::DEBUG

    Config = Hashie::Mash.new(
      kafka_host: 'kafka-cs.sl.cloud9.ibm.com',
      kafka_port: 9092,
      receive_topic: 'config',
      compliance_topic: 'compliance',
      vulnerability_topic: 'vulnerabilityscan',
      notification_topic: 'notification',
      notify_topic: 'test1',
      processor_name: 'sc_server',
      local_job_index: 'local_jobs'
    )

    def self.request_server_sync(offset = 24*60*60)  #default offset is 1day
      SentinelDocker::ESUtil.put(Config.local_job_index, :sync.to_s, {offset: offset})
    end

    def self.request_page_update(page_types=nil)
      page_types ||= [:compliance, :vulnerability] 
      page_types = page_types & [:compliance, :vulnerability]

      page_types.each do |page_type|
        SentinelDocker::ESUtil.put(Config.local_job_index, :report.to_s, {page_type.to_s => true})
      end
    end

    def self.find_req(req_type)
      req = {}
      case req_type
      when :sync
        results = SentinelDocker::ESUtil.find(Config.local_job_index, req_type.to_s)
        offset = 0
        puts "results[sync]=#{results.to_json}"
        results.each do |r|
          offset = r.offset if r.offset && r.offset.to_i > offset
          SentinelDocker::ESUtil.delete(Config.local_job_index, req_type, r.id)
        end
        req[:offset] = offset if offset > 0
      when :report
        results = SentinelDocker::ESUtil.find(Config.local_job_index, req_type.to_s)
        puts "results[report]=#{results.to_json}"
        results.each do |r|
          req[:vulnerability] = true if r.vulnerability
          req[:compliance] = true if r.compliance
          SentinelDocker::ESUtil.delete(Config.local_job_index, req_type.to_s, r.id)
        end
      end
      req
    end

    def self.sync(req)
      offset = req[:offset].to_i
      puts "offset=#{offset}"
      begin_time = Time.at(Time.now.to_i-offset)
      end_time = Time.now
      SentinelDocker::DockerUtil.sync_server_state(begin_time, end_time)
    end

    def self.create_page(req)

      report_types = []
      report_types << 'status_report' if req[:compliance]
      report_types << 'vulnerability_report' if req[:vulnerability]

      Parallel.each(report_types, :in_processes => 0) do |report_type|
        begin
          SentinelDocker::DockerUtil.create_report(report_type)
        rescue => e
          Log.error "Fail to create #{report_type}"
        end
      end

    end

  end
end

