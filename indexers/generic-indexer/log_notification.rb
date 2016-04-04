require 'logstash/filters/base'
require 'logstash/namespace'
require 'json'
require 'digest/sha1'
require 'time'

class LogStash::Filters::LogNotification < LogStash::Filters::Base
  config_name "log_notification"
  milestone 1
  # kafka setup for notifications
  config :broker_list, :validate => :string, :default => 'localhost:9092'
  config :topic_id, :validate => :string, :required => true

  def log_notification(status, uuid, namespace, processor)
    # log this status into a kafka notifications channel
    time = Time.now.utc.iso8601
    time_ms = (Time.now.to_f * 1000.0).to_i
    json = { :status => status, :timestamp => time, :timestamp_ms => time_ms, :namespace => namespace, :uuid => uuid, :processor => processor }
    begin
      @producer.send_msg(@topic_id , nil, JSON[json])
    rescue Exception => e
      @logger.warn("Stack trace: #{e.backtrace.inspect}")
    end
  end
 
  public

  def register
    # kafka setup for notifications
    jarpath = File.join(File.dirname(__FILE__), '../../../vendor/jar/kafka*/libs/*.jar')
    Dir[jarpath].each do |jar|
      require jar
    end
    require 'jruby-kafka'
    options = {
        :broker_list => @broker_list,
        :compression_codec => 'none',
        :compressed_topics => '',
        :request_required_acks => 0,
        :serializer_class => 'kafka.serializer.StringEncoder',
        :partitioner_class => 'kafka.producer.DefaultPartitioner',
        :request_timeout_ms => 10000,
        :producer_type => 'sync',
        :key_serializer_class => nil,
        :message_send_max_retries => 3,
        :retry_backoff_ms => 100,
        :topic_metadata_refresh_interval_ms => 600 * 1000,
        :queue_buffering_max_ms => 5000,
        :queue_buffering_max_messages => 10000,
        :queue_enqueue_timeout_ms => -1,
        :batch_num_messages => 200,
        :send_buffer_bytes => 100 * 1024,
        :client_id => ''

    }
    begin
      @producer = Kafka::Producer.new(options)
      @producer.connect
    rescue Exception => e
      @logger.warn("Stack trace: #{e.backtrace.inspect}")
    end
  end

  def filter(event)
    return unless filter?(event)

    # some metadata for the notification
    processor = event['type']
    uuid = "not/set"
    namespace = "not/set"
   
    log_notification('start', uuid, namespace, processor)
    log_notification('completed', uuid, namespace, processor)

    event.cancel
  end

  def teardown
    @producer.close
  end
end
