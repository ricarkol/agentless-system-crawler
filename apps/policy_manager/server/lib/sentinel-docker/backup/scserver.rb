require 'sentinel-docker'
require 'sentinel-docker/docker_util'
require 'sentinel-docker/scserver_control'
require 'parallel'
require 'profiler'
require 'poseidon'

# RubyVM::InstructionSequence.compile_option = {
#   :trace_instruction => true,
#   :specialized_instruction => false
# }

#Profiler__::start_profile

#Log = SentinelDocker::Log

Log = SentinelDocker::SCServerControl::Log
Config = SentinelDocker::SCServerControl::Config.merge(
  job_clear: false, 
  sync_loop: true, #sync
  run_thread: {enabled: true},  #run
  query_thread: {enabled: true}, #query
  report_thread: {enabled: true}, #report
  ns_detector: {enabled: true}, #ns_detector
  rule_detector: {enabled: true}, #ns_detector
  ns_detector: {enabled: true}, #ns_detector
  )
threads = {}

begin

  SentinelDocker::RuleRunner.clear_running_job

  Log.debug 'start dispatcher'
  loop {
    #sync
    if Config.sync_loop
      begin
        req = SentinelDocker::SCServerControl.find_req(:sync)
        unless req.empty?
          Log.debug 'start sync'
          updated = SentinelDocker::SCServerControl.sync(req)
          Log.debug 'end sync'
        end
      rescue => e
        Log.error "sync error: #{e.message}"
        Log.error e.backtrace.join("\n")
      ensure
      end
    end

    #run
    if Config.run_thread && Config.run_thread.enabled
      if threads[:run] == nil || !threads[:run].alive?
        threads[:run] = Thread.new do
          Log.debug 'start run thread'
          loop {
            SentinelDocker::RuleRunner.run(:in_processes => 1)
            Log.debug "[loop in run] waiting next loop : #{Time.now.iso8601}"
            sleep(5)
          }
          Log.debug 'stop run thread'
        end
      end
    end

    #query
    if Config.query_thread && Config.query_thread.enabled
      if threads[:query] == nil || !threads[:query].alive?
        threads[:query] = Thread.new do
          Log.debug 'start query thread'
          loop {
            SentinelDocker::RuleRunner.query(:in_processes => 1)
            Log.debug "[loop in query] waiting next loop : #{Time.now.iso8601}"
            sleep(10)
          }
          Log.debug 'stop query thread'
        end
      end
    end

    #report
    if Config.report_thread && Config.report_thread.enabled
      if threads[:report] == nil || !threads[:report].alive?
        threads[:report] = Thread.new do
          Log.debug 'start report thread'
          loop {
            begin
              req = SentinelDocker::SCServerControl.find_req(:report)
              unless req.empty?
                Log.debug 'start create_page'
                SentinelDocker::SCServerControl.create_page(req)
                Log.debug 'end create_page'
              end
            rescue => e
              Log.error "report creation error: #{e.message}"
              Log.error e.backtrace.join("\n")
            end

            sleep(2)
          }
          Log.debug 'stop report thread'
        end
      end
    end

    #namespace detector
    if Config.ns_detector && Config.ns_detector.enabled
      if threads[:ns_detector] == nil || !threads[:ns_detector].alive?
        threads[:ns_detector] = Thread.new do
          Log.debug 'start namespace detector thread'
          consumer = Poseidon::PartitionConsumer.new(Config.processor_name, Config.kafka_host, Config.kafka_port,
                                                     Config.receive_topic, 0, :latest_offset)
          loop do
            begin
              messages = consumer.fetch
              messages.each do |m|
                Log.debug "Received message: #{m.value}"
              end
            rescue Poseidon::Errors::UnknownTopicOrPartition
              Log.error "Topic does not exist yet"
            end
            sleep 1
          end
          Log.debug 'stop namespace detector thread'
        end
      end
    end

    #rule_detector
    if Config.rule_detector && Config.rule_detector.enabled
      if threads[:rule_detector] == nil || !threads[:rule_detector].alive?
        threads[:rule_detector] = Thread.new do
          Log.debug 'start rule detector thread'
          consumer = Poseidon::PartitionConsumer.new(Config.processor_name, Config.kafka_host, Config.kafka_port,
                                                     Config.receive_topic, 0, :latest_offset)
          loop do
            begin
              new_scripts = SentinelDocker::DockerUtil.detect_new_rules
              new_scripts.each do |script_path|
                Log.debug "Detect new rule scripts: #{script_path}"
              end
              SentinelDocker::SCServerControl.request_server_sync unless new_scripts.empty?
            rescue => e
              Log.error "fail to find new rule scirpts"
              Log.error e.backtrace.join("\n")
            end
            sleep 1
          end
          Log.debug 'stop rule detector thread'
        end
      end
    end

    # compliance_detector TODO
    if Config.compliance_detector && Config.compliance_detector.enabled
      if threads[:compliance_detector] == nil || !threads[:compliance_detector].alive?
        threads[:compliance_detector] = Thread.new do
          Log.debug 'start compliance detector thread'
          consumer = Poseidon::PartitionConsumer.new(Config.processor_name, Config.kafka_host, Config.kafka_port,
                                                     Config.compliance_topic, 0, :latest_offset)
          loop do
            begin
              messages = consumer.fetch
              messages.each do |m|
                Log.debug "Received message: #{m.value}"
              end
            rescue Poseidon::Errors::UnknownTopicOrPartition
              Log.error "Topic does not exist yet"
            end
            sleep 1
          end
          Log.debug 'stop compliance detector thread'
        end
      end
    end

    #vulnerability_detector  TODO
    if Config.vulnerability_detector && Config.vulnerability_detector.enabled
      if threads[:vulnerability_detector] == nil || !threads[:vulnerability_detector].alive?
        threads[:vulnerability_detector] = Thread.new do
          Log.debug 'start vulnerability detector thread'
          consumer = Poseidon::PartitionConsumer.new(Config.processor_name, Config.kafka_host, Config.kafka_port,
                                                     Config.vulnerability_topic, 0, :latest_offset)
          loop do
            begin
              messages = consumer.fetch
              messages.each do |m|
                Log.debug "Received message: #{m.value}"
              end
            rescue Poseidon::Errors::UnknownTopicOrPartition
              Log.error "Topic does not exist yet"
            end
            sleep 1
          end
          Log.debug 'stop vulnerability detector thread'
        end
      end
    end

    sleep(3)
    #break

  }
  Log.debug 'stop dispatcher'

rescue => e
  puts e.message
  puts e.backtrace.join("\n")
  Log.error "error : #{e.message}"
  Log.error e.backtrace.join("\n")
ensure
  puts threads
  threads.each do |k, th|
    Thread.kill(th) if th
    Log.debug "thread #{k} killed" if th
  end
  Log.debug "all threads have been terminated safely"

end

