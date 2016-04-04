require "logstash/outputs/base"
require "logstash/namespace"

require "stud/buffer"
require "rest_client"


class LogStash::Outputs::CloudSight < LogStash::Outputs::Base

  include Stud::Buffer

  config_name "cloudsight"
  milestone 1
  
  # The CloudSight gateway host
  config :host, :validate => :string, :default => "127.0.0.1"
  
  # The default port to connect on.
  config :port, :validate => :number, :default => 8080
  
  # The CloudSight channel to which the log events will be sent 
  config :channel, :validate => :string, :default => nil
  
  # The CloudSight namespace to be associated with the log events 
  config :namespace, :validate => :string, :default => 'default_namespace'
  
  # Identifies the log file type, which is important for type-specific log parsing and analytics
  config :type, :validate => :string, :required => true
  
  # Determines what contents to send for each log event.
  # Possible values are:
  #  - 'full_event': The entire event, as received by this plugin, is sent out.
  #  - 'message': Only the 'message' field is sent out
  config :format, :validate => ["full_event", "message"], :default => "full_event"
  
  # Set to true if you want multiple log events to be batched in a POST to the Cloudsight broker 
  # instead of one POST event.  
  #
  # If true, we make a POST every "batch_events" events or
  # "batch_timeout" seconds (whichever comes first).
  config :batch, :validate => :boolean, :default => false

  # If batch is set to true, the number of events we queue up
  config :batch_events, :validate => :number, :default => 50

  # If batch is set to true, the maximum amount of time between POST calls
  # when there are pending events to flush.
  config :batch_timeout, :validate => :number, :default => 5
  
  def register
    if @batch
      buffer_initialize(
        :max_items => @batch_events,
        :max_interval => @batch_timeout,
        :logger => @logger
      )
    end
     
    @cloudsight_url = "http://#{@host}:#{@port}/broker/v0/data?origin=logstash:#{@type}"
    @content_type = (@format == "message") ? 'text/plain' : 'application/json'
    
    @logger.info("Registered 'cloudsight' output plugin")
  end
  
  def receive(event)
    return unless output?(event)
    
    namespace = event.sprintf(@namespace)
    
    if @format == "message"
      processed_event = event['message'] 
    else
      processed_event = event.to_json
    end

    if @batch
      # Group log events per namespace. Since the log file path should be part of the namespace,
      #it will be unique per log file.
      @logger.debug("Buffered event for namespace '#{namespace}'. Processed event: #{processed_event}")
      buffer_receive(processed_event, namespace)
      return
    end
    
    post(add_namespace_and_type_to_url(@cloudsight_url, namespace), processed_event, @content_type)
  end
  
  # called from Stud::Buffer#buffer_flush when there are events to flush
  def flush(events, key, teardown=false)
    # The key will contain the namespace under which the events have been grouped
    post(add_namespace_and_type_to_url(@cloudsight_url, key), events.to_s, @content_type)
  end
  
  private
  
  def post(uri, payload, content_type)
    begin
      response = RestClient.post uri, payload, :content_type => content_type
      if response.code != 200
        @logger.error("Cloudsight returned status code #{response.code} when the plugin was posting to the broker; Response = #{response}; Payload: << #{payload} >>")
      end
    rescue => e
      @logger.error("Error while posting the following event(s) to CloudSight: << #{payload} >>; Exception: #{e}")
    end
  end
  
  def add_namespace_and_type_to_url(base_url, resolved_namespace)
    channel_type = @channel.nil? ? '' : "&type=#{@channel}"
    return "#{base_url}&namespace=#{resolved_namespace}#{channel_type}"
  end
end
