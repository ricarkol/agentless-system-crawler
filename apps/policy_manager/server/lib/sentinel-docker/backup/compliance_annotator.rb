require 'sentinel-docker'
require 'hashie'
require 'logger'
require 'parallel'
require 'profiler'
require 'json'
require 'poseidon'

#Log = SentinelDocker::Log
Log = Logger.new(STDOUT)
Log.level = Logger::DEBUG

Config = Hashie::Mash.new(
  kafka_host: 'kafka-cs.sl.cloud9.ibm.com',
  kafka_port: 9092,
  #receive_topic: 'config',
  receive_topic: 'config',
  #receive_topic: 'compliance',
  #receive_topic: 'notification',
  notify_topic: 'test1',
  processor_name: 'sc_server'
)

# Producer_options = {
#   topic: Config.notify_topic,
#   host: Config.kafka_host,
#   port: Config.kafka_port
# }

# Consumer_options = {
#   topic: Config.receive_topic,
#   host: Config.kafka_host,
#   port: Config.kafka_port,
#   offset: -2,
#   max_size: Config.max_size,
#   polling: Config.polling_interval
# }

consumer_thread = nil
producer_thread = nil

begin


  #compliance consumer (receive result and do save_rule_run)
  #config consumer (receive new)
  #notification consumer (receive new namespace/crawl_time)
  #notification producer (send server state, "container detected" "image detected", "trigger rule", "receive results")
  #periodic_action ()
  
  consumer_thread = Thread.new do
    consumer = Poseidon::PartitionConsumer.new(Config.processor_name, Config.kafka_host, Config.kafka_port,
                                               Config.receive_topic, 0, :earliest_offset)
    loop do
      begin
        messages = consumer.fetch
        messages.each do |m|
          Log.debug "Received message: #{m.value}"
          metadata = JSON.parse(m.value) if m.topic = 'metadata'
          conf = {
            namespace: metadata['timestamp'],
            container_name: metadata['container_name'],
            container_image_id: metadata['container_image'],
            container_long_id: metadata['container_long_id'],
            timestamp: metadata['timestamp']
          }
          #sync for this namespace only
        end

        #dockerinspect by container_long_id (dockerinspect.Name)
        #dockerhistory by dockerimage_id   (feature_key, namespace, timestamp, created, created_by, size)

        #notification ---> add attributes ---> sync for this namespace only (skip namespace query & crawltimes query, go to rules)


        end
      rescue Poseidon::Errors::UnknownTopicOrPartition
        Log.debug "Topic does not exist yet"
      end
      sleep 1
    end

  end

  producer_thread = Thread.new do
    producer = Poseidon::Producer.new(["#{Config.kafka_host}:#{Config.kafka_port}"], Config.processor_name)
    loop do
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

      sleep 10
    end
  end

  consumer_thread.join
  producer_thread.join

rescue => e
  Log.debug "run error: #{e.message}"
  Log.debug e.backtrace.join("\n")
ensure

  Thread.kill(consumer_thread) if consumer_thread
  Thread.kill(producer_thread) if producer_thread
  Log.debug "all threads have been terminated safely"
end


def send_messages(namespace, status)

  producer = Poseidon::Producer.new(["#{Config.kafka_host}:#{Config.kafka_port}"], Config.processor_name)
  message = {
        processor: Config.processor_name,
        status: status,
        namespace: namespace,
        timestamp: Time.now.iso8601(6)
  }
  producer.send_messages([Poseidon::MessageToSend.new(Config.notify_topic, message.to_json)])
  Log.debug "Sent message: #{message.to_json}"

end


# def notify(namespace, status)

#   message = {
#     processor: Config.processor_name,
#     status: status,
#     namespace: namespace,
#     timestamp: Time.now.iso8601
#   }

#   #notify status
#   producer = Kafka::Producer.new(Producer_options)
#   snd_msg = Kafka::Message.new(message.to_json)
#   producer.push([snd_msg])

# end


# begin

#   #read offset
#   consumer = Kafka::Consumer.new(Consumer_options)
#   offset = consumer.offset
#   puts "offset=#{offset}"

#   notify('namespace1', 'success')

#   consumer.loop do |rcv_msgs|

#     puts "rcv_msgs=#{rcv_msgs}"

#     #detect new namespace
#     rcv_msgs.each do |rcv_msg|

#       stream = StringIO.new(rcv_msgs)
#       CSV.open(stream, field_size_limit: Fixnum::MAX, col_sep: "\t", quote_char: "'") do |ftype, fkey, fvalue|
#         puts "ftype=#{ftype}, fkey=#{fkey}, fvalue=#{fvalue}"
#         metadata = JSON.parse(fvalue) if ftype == 'metadata'
#         namespace = metadata['namespace']
#         timestamp = metadata['timestamp']
#         puts "namespace=#{namespace}, timestamp=#{timestamp}"
#       end
#     end

#     #notify(namespace, 'register new container')
#     offset = consumer.offset
#     put "offset=#{offset}"

#   end

# rescue => e
#   Log.error "Error: #{e.message}"
#   Log.error e.backtrace.join("\n")
# ensure
#   #store offset in DB
#   puts "store offset <#{offset}> in DB"
# end
