# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "socket"
require "thread"
require "openssl"

# This queue implementation was copied from http://spin.atomicobject.com/2014/07/07/ruby-queue-pop-timeout/
class QueueWithTimeout
  def initialize
    @mutex = Mutex.new
    @queue = []
    @recieved = ConditionVariable.new
  end
 
  def <<(x)
    @mutex.synchronize do
      @queue << x
      @recieved.signal
    end
  end
 
  def pop(non_block = false)
    pop_with_timeout(non_block ? 0 : nil)
  end
 
  def pop_with_timeout(timeout = nil)
    @mutex.synchronize do
      if @queue.empty?
        @recieved.wait(@mutex, timeout) if timeout != 0
        #if we're still empty after the timeout, raise exception
        raise ThreadError, "queue empty" if @queue.empty?
      end
      @queue.shift
    end
  end
end

# All the other code is basically the graphite plugin with some pieces from the mtlumberjack plugin.

# This output allows you to pull metrics from your logs and ship them to
# MTGraphite. MTGraphite is an open source tool for storing and graphing metrics.
#
# An example use case: Some applications emit aggregated stats in the logs
# every 10 seconds. Using the grok filter and this output, it is possible to
# capture the metric values from the logs and emit them to MTGraphite.
class LogStash::Outputs::MTMTGraphite < LogStash::Outputs::Base
  config_name "mtgraphite"
  milestone 2

  EXCLUDE_ALWAYS = [ "@timestamp", "@version" ]

  DEFAULT_METRICS_FORMAT = "*"
  METRIC_PLACEHOLDER = "*"

  # The hostname or IP address of the MTGraphite server.
  config :host, :validate => :string, :default => "localhost"

  # The port to connect to on the MTGraphite server.
  config :port, :validate => :number, :default => 9095

  config :supertenant_id, :validate => :string, :default => "Crawler"
  config :supertenant_password, :validate => :string, :default => "oLYMLA7ogscT"

  # Interval between reconnect attempts to Carbon.
  config :reconnect_interval, :validate => :number, :default => 2

  # Should metrics be resent on failure?
  config :resend_on_failure, :validate => :boolean, :default => false

  # The metric(s) to use. This supports dynamic strings like %{host}
  # for metric names and also for values. This is a hash field with key 
  # being the metric name, value being the metric value. Example:
  #
  #     [ "%{host}/uptime", "%{uptime_1m}" ]
  #
  # The value will be coerced to a floating point value. Values which cannot be
  # coerced will be set to zero (0). You may use either `metrics` or `fields_are_metrics`,
  # but not both.
  config :metrics, :validate => :hash, :default => {}

  # An array indicating that these event fields should be treated as metrics
  # and will be sent verbatim to MTGraphite. You may use either `fields_are_metrics`
  # or `metrics`, but not both.
  config :fields_are_metrics, :validate => :boolean, :default => false

  # Include only regex matched metric names.
  config :include_metrics, :validate => :array, :default => [ ".*" ]

  # Exclude regex matched metric names, by default exclude unresolved %{field} strings.
  config :exclude_metrics, :validate => :array, :default => [ "%\{[^}]+\}" ]

  # Enable debug output.
  config :debug, :validate => :boolean, :default => false, :deprecated => "This setting was never used by this plugin. It will be removed soon."

  # Defines the format of the metric string. The placeholder '*' will be
  # replaced with the name of the actual metric.
  #
  #     metrics_format => "foo.bar.*.sum"
  #
  # NOTE: If no metrics_format is defined, the name of the metric will be used as fallback.
  config :metrics_format, :validate => :string, :default => DEFAULT_METRICS_FORMAT

  def send_metrics(messages)
    @logger.debug("Sending carbon messages", :messages => messages, :host => @host, :port => @port)

    # Catch exceptions like ECONNRESET and friends, reconnect on failure.
    # TODO(sissel): Test error cases. Catch exceptions. Find fortune and glory.
    begin
      len_messages = messages.length
      @socket.syswrite(["1W"].pack("A*"))
      #@socket.syswrite([len_messages].pack("I!"))
      @socket.syswrite([len_messages].pack("N"))
      for msg in messages
        len_message = msg.size()
        @socket.syswrite(["1M"].pack("A*"))
        @socket.syswrite([@sequence].pack("N"))
        @socket.syswrite([len_message].pack("N"))
        @socket.syswrite([msg].pack("A*"))
        @sequence += 1
      end
      response = @socket.sysread(6)
      ack = response.unpack("A*N")

      # XXX ack[0] is not really 1A
      if ack[0] == "1A"
        @logger.debug("Confirmed write to mtgraphite")
      else
        @logger.debug("Failed write to mtgraphite")
      end

    rescue EOFError => e
      puts e
      @logger.warn(:exception => e, :host => @host, :port => @port)
      @socket.sysclose()
      sleep(@reconnect_interval)
      connect
    rescue Errno::EPIPE, Errno::ECONNRESET => e
      @logger.warn("Connection to mtgraphite server died",
                   :exception => e, :host => @host, :port => @port)
      sleep(@reconnect_interval)
      connect
      retry if @resend_on_failure
    end
  end

  def register
    @include_metrics.collect!{|regexp| Regexp.new(regexp)}
    @exclude_metrics.collect!{|regexp| Regexp.new(regexp)}

    if @metrics_format && !@metrics_format.include?(METRIC_PLACEHOLDER)
      @logger.warn("metrics_format does not include placeholder #{METRIC_PLACEHOLDER} .. falling back to default format: #{DEFAULT_METRICS_FORMAT.inspect}")

      @metrics_format = DEFAULT_METRICS_FORMAT
    end

    @queue = QueueWithTimeout.new
    Thread.new do
      connect
      while true
        begin
          msg = @queue.pop_with_timeout(5)
          puts "popped #{msg}"
          send_metrics(msg)
        rescue ThreadError => e
          # timeout
          @socket.syswrite(["1", "I", @identification_size, @identification].pack("AACA#{@identification_size}"))
        end
      end
    end
  end # def register

  def connect
    # TODO(sissel): Test error cases. Catch exceptions. Find fortune and glory. Retire to yak farm.
    begin
      @sequence = 1
      tcp_socket = TCPSocket.new(@host, @port)
      @ssl = OpenSSL::SSL::SSLContext.new(:TLSv1)
      @ssl.ssl_version = "TLSv1"  
      @socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, @ssl)
      @socket.sync_close = true
      @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
      @socket.connect

      tenant_id_size = @supertenant_id.size()
      tenant_password_size = @supertenant_password.size()
      @my_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3]

      @identification = "crawler_stats_#{@my_ip}"
      @identification_size = @identification.size()

      @socket.syswrite(["1", "I", @identification_size, @identification].pack("AACA#{@identification_size}"))
      @socket.syswrite(["2S"].pack("A*"))
      @socket.syswrite([tenant_id_size].pack("C"))
      @socket.syswrite([@supertenant_id].pack("A*"))
      @socket.syswrite([tenant_password_size].pack("C"))
      @socket.syswrite([@supertenant_password].pack("A*"))

      response = @socket.sysread(6)
      ack = response.unpack("A*N")
      puts ack
      if ack[0] == "0A"
        @socket.sysclose()
        raise ArgumentError.new('Invalid tenant authorization. Please, check the tenant id and password!')
      end

      puts "connecting to #{@host}"
    rescue Errno::ECONNREFUSED => e
      @logger.warn("Connection refused to mtgraphite server, sleeping...",
                   :host => @host, :port => @port)
      sleep(@reconnect_interval)
      retry
    end
  end # def connect

  def construct_metric_name(metric)
    if @metrics_format
      return @metrics_format.gsub(METRIC_PLACEHOLDER, metric)
    end

    metric
  end

  public
  def receive(event)
    return unless output?(event)

    # MTGraphite message format: metric value timestamp\n

    messages = []
    timestamp = event.sprintf("%{+%s}")

    if @fields_are_metrics
      @logger.debug("got metrics event", :metrics => event.to_hash)
      event.to_hash.each do |metric,value|
        next if EXCLUDE_ALWAYS.include?(metric)
        next unless @include_metrics.empty? || @include_metrics.any? { |regexp| metric.match(regexp) }
        next if @exclude_metrics.any? {|regexp| metric.match(regexp)}
        messages << "#{construct_metric_name(metric)} #{event.sprintf(value.to_s).to_f} #{timestamp}"
      end
    else
      @metrics.each do |metric, value|
        @logger.debug("processing", :metric => metric, :value => value)
        metric = event.sprintf(metric)
        next unless @include_metrics.any? {|regexp| metric.match(regexp)}
        next if @exclude_metrics.any? {|regexp| metric.match(regexp)}
        messages << "#{construct_metric_name(event.sprintf(metric))} #{event.sprintf(value).to_f} #{timestamp}"
      end
    end

    if messages.empty?
      @logger.info("Message is empty, not sending anything to MTGraphite", :messages => messages, :host => @host, :port => @port)
    else
      @queue << messages
    end
  end # def receive
end # class LogStash::Outputs::MTGraphite
