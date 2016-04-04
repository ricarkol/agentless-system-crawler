# encoding: utf-8
require 'logstash/namespace'
require 'logstash/outputs/base'
require 'stud/buffer'

class LogStash::Outputs::MTLumberjack < LogStash::Outputs::Base
  
  # Used for buffering log events
  include Stud::Buffer

  config_name "mtlumberjack"
  milestone 1

  # list of addresses lumberjack can send to
  config :hosts, :validate => :array, :required => true

  # the port to connect to
  config :port, :validate => :number, :required => true

  # ssl certificate to use
  config :ssl_certificate, :validate => :path, :required => false

  # window size: batch up to this many log events
  config :window_size, :validate => :number, :default => 10
  
  # window timeout in seconds: if we do not accumulate window_size events within this time, send what we have
  config :window_timeout, :validate => :number, :default => 5
  
  # Bluemix space id
  config :tenant_id, :validate => :string, :required => false
  
  # Bluemix logging password
  config :tenant_password, :validate => :string, :required => false
  
  # Alchemy supertenant id
  config :supertenant_id, :validate => :string, :required => false
  
  # Alchemy supertenant password
  config :supertenant_password, :validate => :string, :required => false

  public
  def register
    # Used for managing the buffer of log events (window)
    buffer_initialize(
      :max_items => @window_size,
      :max_interval => @window_timeout,
      :logger => @logger
    )
    
    require 'mtlumberjack/client'
    connect

    @codec.on_event do |payload|
      #begin
        #@client.write({ 'line' => payload })
        #@logger.debug("Payload = <<#{payload}>>")
        
        buffer_receive({ 'line' => payload })
        @logger.debug("Buffered event with payload <<#{payload}>>")
      #rescue Exception => e
      #  @logger.error("Client write error, trying connect", :e => e, :backtrace => e.backtrace)
      #  connect
      #  retry
      #end # begin
    end # @codec
  end # def register

  public
  def receive(event)
    return unless output?(event)
    if event == LogStash::SHUTDOWN
      finished
      return
    end # LogStash::SHUTDOWN
    @codec.encode(event)
  end # def receive
  
  # called from Stud::Buffer#buffer_flush when there are events to flush
  def flush(events, teardown=false)
    @logger.debug("About to flush events: #{events}")
    @client.write_events(events)
  end
  
  # called from Stud::Buffer#buffer_flush when an error occurs
  def on_flush_error(e)
    @logger.warn("An unexpected error occurred while sending a backlog of events to server. Reconnecting...",
      :exception => e,
      :backtrace => e.backtrace
    )
    connect
  end
  
  public
  def teardown
    buffer_flush(:final => true)
  end

  private 
  def connect
    require 'resolv'
    @logger.info("Connecting to mtlumberjack server.", :addresses => @hosts, :port => @port, 
        :ssl_certificate => @ssl_certificate, :window_size => @window_size)
    begin
      ips = []
      @hosts.each { |host| ips += Resolv.getaddresses host }
      mt_options = {
        :addresses => ips.uniq, :port => @port, 
        :window_size => @window_size, :logger => @logger
      }
      mt_options[:tenant_id] = @tenant_id if @tenant_id
      mt_options[:tenant_password] = @tenant_password if @tenant_password 
      mt_options[:supertenant_id] = @supertenant_id if @supertenant_id
      mt_options[:supertenant_password] = @supertenant_password if @supertenant_password
      @client = MTLumberjack::Client.new(mt_options)
    rescue ArgumentError => e
      # We need to stop because the user provided invalid argument(s) to the plugin (e.g. invalid credentials)
      @logger.error("Invalid arguments: #{e.message} --- Aborting!")
      finished
      return
    rescue => e
      @logger.error("All hosts unavailable, sleeping", :hosts => ips.uniq, :e => e, 
        :backtrace => e.backtrace)
      sleep(10)
      retry
    end
  end
end
