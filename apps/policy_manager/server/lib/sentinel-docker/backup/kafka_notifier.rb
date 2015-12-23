require 'sentinel-docker'
require 'sentinel-docker/docker_util'
require 'sentinel-docker/scserver_control'
require 'parallel'
require 'profiler'
require 'poseidon'

Log = SentinelDocker::SCServerControl::Log

module SentinelDocker
  module NotificationAPI

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

    class Notifier

      

    end

    self.producer = nil

    self

    producer = Poseidon::Producer.new(["#{Config.kafka_host}:#{Config.kafka_port}"], Config.processor_name)
    status = 'test_status'
    namespace = 'test_namespace'


    message = {
      processor: Config.processor_name,
      status: status,
      namespace: namespace,
      timestamp: Time.now.iso8601(6)
    }

    producer.send_messages([Poseidon::MessageToSend.new(Config.notify_topic, message.to_json)])
    Log.debug "Sent message: #{message.to_json}"

    end


  end
end



