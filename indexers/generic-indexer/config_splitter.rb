require 'logstash/filters/base'
require 'logstash/namespace'
require 'json'
require 'digest/sha1'
require 'time'

class LogStash::Filters::ConfigSplitter < LogStash::Filters::Base
  config_name "config_splitter"
  milestone 1
  # kafka setup for notifications
  config :broker_list, :validate => :string, :default => 'localhost:9092'
  config :topic_id, :validate => :string, :required => true
  config :group_id, :validate => :string, :required => true
  config :container_name, :validate => :string, :required => true

  def log_notification(status, uuid, namespace, processor)
    # log this status into a kafka notifications channel
    time = Time.now.utc.iso8601(6)
    time_ms = (Time.now.to_f * 1000.0).to_i
    json = { :status => status, :timestamp => time, :timestamp_ms => time_ms, :namespace => namespace, 
             :uuid => uuid, :processor => @group_id, :"instance-id" => @container_name }
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
    uuid = "not/available"
    namespace = "not/available"
   
    first_line = true
    metadata_hash = {}
    event['message'].each_line do |feature|
      feature.chop!
      @logger.debug("Processing feature: <<< #{feature} >>>")
        if first_line
          # We must collect the frame's metadata sent by the crawler
          metadata_hash = JSON.parse(feature)
          @logger.debug("Collecting frame's metadata: <<< #{metadata_hash.inspect} >>>")
          uuid = metadata_hash['uuid']
          namespace = metadata_hash['namespace']
          log_notification('start', uuid, namespace, processor)
          @logger.warn("start processing: namespace: #{namespace}, uuid: #{uuid}")

          first_line = false
        else
          # We must index the current feature, adding to it the metadata previously collected
          @logger.debug("Matched: extracted feature string: <<< #{feature} >>>")
          begin
                extracted_feature_hash = JSON.parse(feature)
                e = LogStash::Event.new(extracted_feature_hash)
                yield e
          rescue => error
          	@logger.warn("Could not extract feature: <<< #{feature} >>>") 
          	@logger.warn("Stack trace: #{error.backtrace}") 
                log_notification('error', uuid, namespace, processor)

          	next
          end
        end
    end

    log_notification('completed', uuid, namespace, processor)
    @logger.warn("end processing: namespace: #{namespace}, uuid: #{uuid}")

    event.cancel
  end

  def teardown
    @producer.close
  end
end
