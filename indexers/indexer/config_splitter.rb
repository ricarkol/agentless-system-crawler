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
  config :config_filter, :validate => :string, :required => false
  config :keyword_filter, :validate => :array, :required => false

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

  def in_keyword(feature_key)
     keyword_filter.each do |filterv|
        @logger.info("filterv: <<< #{filterv} >>>")
        if feature_key.start_with? filterv then
           @logger.info("key_match: << #{filterv} #{feature_key} >>")
           return true
        end
     end  
     return false
  end
           
  def in_content(value_json)
    value_json.each do |fkey, fvalue|
       @logger.info("fvalue: <<< #{fvalue} >>>")
       if fvalue.is_a?(::Hash) then
           next
       end
       keyword_filter.each do |filterv|
         if fvalue.start_with? filterv then
            @logger.info("content_match print: << #{filterv} #{fvalue} >>")
            return true
         end
       end   
    end
    return false
  end

  def filter(event)
    return unless filter?(event)

    # some metadata for the notification
    processor = event['type']
    uuid = "not/available"
    namespace = "not/available"


    @logger.info("myconfigfilter: <<< #{config_filter} >>>")
    @logger.info("mykeywordfilter: <<< #{keyword_filter} >>>")
    first_line = true
    metadata_hash = {}
    event['message'].each_line do |feature|
      feature.chop!
#      @logger.info("Processing feature: <<< #{feature} >>>")
      m = feature.match(/(.+?)\s+"(.+?)"\s+[",']?(\{.+?\})[",']?$/)
      if m
        if first_line
          # We must collect the frame's metadata sent by the crawler
          metadata_hash = JSON.parse(m[3])
#          @logger.info("Collecting frame's metadata: <<< #{metadata_hash.inspect} >>>")
          uuid = metadata_hash['uuid']
          namespace = metadata_hash['namespace']
          log_notification('start', uuid, namespace, processor)
          @logger.warn("start processing: namespace: #{namespace}, uuid: #{uuid}")

          first_line = false
        else
          # We must index the current feature, adding to it the metadata previously collected
          feature_key_hash = Digest::SHA1.hexdigest("#{m[1]}#{m[2]}") # SHA1 hash of feature type and key given by crawler
          feature_contents_hash = Digest::SHA1.hexdigest(m[3]) # SHA1 hash of feature contents
          extracted_feature_str = "{\"feature_type\":\"#{m[1]}\", \"feature_key\":\"#{m[2]}\", \"key_hash\":\"#{feature_key_hash}\", \"contents_hash\": \"#{feature_contents_hash}\",  \"#{m[1]}\": #{m[3]}, \"type\": \"config_crawler\"}"
          feature_type = m[1]
          feature_key = m[2]
          feature_content = m[3]

          @logger.info("Processing feature key: <<< #{feature_key} >>>")
          @logger.info("Processing feature type: <<< #{feature_type} >>>")
          @logger.info("Processing feature content: <<< #{feature_content} >>>")
          if feature_type.start_with? config_filter then
#              feature_content_json = JSON.parse(feature_content)
#              @logger.info("feature_content_json: <<< #{feature_content_json} >>>")
              if self.in_keyword(feature_key) then
                 next
              end
          end
#          @logger.info("Matched: extracted feature string: <<< #{extracted_feature_str} >>>")
          begin
             extracted_feature_hash = JSON.parse(extracted_feature_str)
             e = LogStash::Event.new(extracted_feature_hash.merge!(metadata_hash))
             yield e
          rescue => error
      	     @logger.warn("Could not extract feature: <<< #{feature} >>>") 
       	     @logger.warn("Stack trace: #{error.backtrace}") 
             log_notification('error', uuid, namespace, processor)
      	     next
          end
        end      
#        @logger.warn("Could not match feature: <<< #{feature} >>>")
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
