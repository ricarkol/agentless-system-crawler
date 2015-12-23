require "socket"
require "thread"
require "openssl"
require "zlib"
require "json"

module MTLumberjack
  
  # Attribute names for data that can be added to log events
  ALCHEMY_TENANT_ID_KEY = "ALCH_TENANT_ID"
  GROUP_ID_KEY = 'group_id'
  INSTANCE_ID_KEY = 'instance'
  
  # Base directory on the host to which the log crawler will map container's log files
  INTROSPECTION_HOST_BASE_DIR = "/var/log/crawler_container_logs"
  
  LS_TIMESTAMP = '@timestamp' # Label of logstash event's timestamp attribute
  LB_TIMESTAMP = "timestamp" # Label of our timestamp attribute
  
  # How long we wait for an ACK from the lumberjack server before considering the connection has been lost
  ACK_READ_TIMEOUT = 30 # seconds
  
  # How long we wait for the write buffer of the socket to be ready
  WRITE_TIMEOUT = 60 # seconds
  
  # Connection timeout
  CONNECT_TIMEOUT = 60 # seconds
  
  SEQUENCE_MAX = (2**(0.size * 8 -2) -1)
  
  public
  def self.set_logger(logger)
    @@logger = logger
  end
  
  public
  def self.get_logger()
    @@logger
  end
  
  class Client
    def initialize(opts={})
      @opts = {
        :port => 0,
        :addresses => []
      }.merge(opts)
      
      logger = @opts.delete(:logger)
      MTLumberjack.set_logger(logger)

      @opts[:addresses] = [@opts[:addresses]] if @opts[:addresses].class == String
      raise ArgumentError.new("Must set a port.") if @opts[:port] == 0
      raise ArgumentError.new("Must set at least one address") if @opts[:addresses].empty?

      @socket = connect
    end

    private
    def connect
      addrs = @opts[:addresses].shuffle
      begin
        opts = @opts
        opts[:address] = addrs.pop
        MTLumberjack::MTSocket.new(opts)
      rescue *[Errno::ECONNREFUSED,SocketError]
        retry
      end
    end

    public
    def write(hash)
      @socket.write_hash(hash)
    end
    
    public
    def write_events(events)
      @socket.write_events(events)
    end

    public
    def host
      @socket.host
    end
  end

  class MTSocket
    attr_reader :sequence
    attr_reader :window_size
    attr_reader :host
    
    # Create a new MTLumberjack Socket.
    #
    # - options is a hash. Valid options are:
    #
    # * :port - the port to listen on
    # * :address - the host/address to bind to
    # * :ssl_certificate - the path to the ssl cert to use
    # * :window_size - how many frames to send before we wait for an ACK
    def initialize(opts={})
      @opts = {
        :port => 0,
        :address => "127.0.0.1",
        :ssl_certificate => nil,
        :window_size => 10
      }.merge(opts)
      
      @socket_mutex = Mutex.new
      
      @sequence = 0
      @last_ack = 0
      
      connect
            
      Thread.new do
         while true
           begin
             MTLumberjack.get_logger().info('Sleeping before sending probe with identification...', :host => @identification)
             sleep(3)
             @socket_mutex.synchronize do 
               @socket.syswrite(["1", "I", @identification_size, @identification].pack("AACA#{@identification_size}"))
               @socket.flush()
             end
           rescue => e
             MTLumberjack.get_logger().warn("An unexpected error occurred in the probing thread. It will continue despite it.",
               :exception => e,
               :backtrace => e.backtrace, 
               :host => @identification
             )
             sleep(10)
             retry
           end
         end   
      end
    end
    
    private
    def connect
      @socket_mutex.synchronize do
        
        @host = @opts[:address]
        @window_size = @opts[:window_size]
        #@window_size = 1
        
        # Set tenant id and password, giving precedence to a supertenant id if given
        # Also, determine if the authentication will be done by a tenant (T) or a supertenant (S)
        @tenant_id = ""
        @tenant_password = ""
        @auth_frame_type = 'T'
        if @opts.has_key?(:supertenant_id)
           @tenant_id = @opts[:supertenant_id]
           @tenant_password = @opts.has_key?(:supertenant_password) ? @opts[:supertenant_password] : ""
           @auth_frame_type = 'S'
           MTLumberjack.get_logger().debug("Will use supertenant id and password for authentication.")
        elsif @opts.has_key?(:tenant_id)
           @tenant_id = @opts[:tenant_id]
           @tenant_password = @opts.has_key?(:tenant_password) ? @opts[:tenant_password] : ""
        end
        MTLumberjack.get_logger().info("Will authenticate with tenant_id '#{@tenant_id}'")# and password '#{@tenant_password}'")
        MTLumberjack.get_logger().info("Target host = #{@opts[:address]}:#{@opts[:port]}")
  
        if @opts[:ibm_java]
          MTLumberjack.get_logger().debug("IBM Java was flagged as used. Resorting to the SSL socket wrapper.")
          
          $CLASSPATH << File.join(File.expand_path(File.dirname(__FILE__)), '..', '..', 'target', 'classes')
          require 'mtlumberjack/ssl_socket_wrapper'
          @socket = MTLumberjack::SSLSocket.new(@opts[:address], @opts[:port])
          @socket.connect()
          
          # Make sure the underlying Java socket read timeout is set (in milliseconds).
          # If no underlying Java socket is used we rely on IO.select for timing out.
          @socket.set_read_timeout(MTLumberjack::ACK_READ_TIMEOUT * 1000)
        else
          MTLumberjack.get_logger().info("Initializing TCP socket")
          addr = Socket.getaddrinfo(@opts[:address], nil)
          sockaddr = Socket.pack_sockaddr_in(@opts[:port], addr[0][3])
          @tcp_socket = Socket.new(Socket.const_get(addr[0][0]), Socket::SOCK_STREAM, 0)
          @tcp_socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
          MTLumberjack.get_logger().info("Trying to perform a non-blocking TCP connection")
          non_blocking_tcp_connect(@tcp_socket, sockaddr)
          MTLumberjack.get_logger().info("TCP connection established")

          @ssl = OpenSSL::SSL::SSLContext.new(:TLSv1)
          @ssl.ssl_version = "TLSv1"  
          @socket = OpenSSL::SSL::SSLSocket.new(@tcp_socket, @ssl)
          @socket.sync_close = true
          MTLumberjack.get_logger().info("Trying to perform a non-blocking SSL connection")
          non_blocking_ssl_connect(@socket)
          MTLumberjack.get_logger().info("SSL connection established")
          
          
#          @tcp_socket = TCPSocket.new(@opts[:address], @opts[:port])
#          #openssl_cert = OpenSSL::X509::Certificate.new(File.read(@opts[:ssl_certificate])) unless @opts[:ssl_certificate].nil?
#          @ssl = OpenSSL::SSL::SSLContext.new(:TLSv1)
#          @ssl.ssl_version = "TLSv1"  
#          @socket = OpenSSL::SSL::SSLSocket.new(@tcp_socket, @ssl)
#          @socket.sync_close = true
#          @socket.connect
#          @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
        end
  
        #if @socket.peer_cert.to_s != openssl_cert.to_s
        #  raise "Client and server certificates do not match."
        #end
              
        tenant_id_size = @tenant_id.size()
        tenant_password_size = @tenant_password.size()
  
        @my_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3]
        @host_name = Socket.gethostname
        if @auth_frame_type == 'S'
          @identification = "log_crawler_#{@my_ip}_#{@host_name}"
        else
          @identification = "standalone_mtlumberjack_client_#{@my_ip}_#{@host_name}"
        end
        @identification_size = @identification.size()
       
       # Send log crawler identification to the server 
        MTLumberjack.get_logger().info("About to send the identification to the server: <<#{@identification}>> (len = #{@identification_size})")
        @socket.syswrite(["1", "I", @identification_size, @identification].pack("AACA#{@identification_size}"))
        
        # Send tenant (or supertenant) id and password to the server
        #MTLumberjack.get_logger().debug("About to send tenant id <<#{@tenant_id}>> (len = #{tenant_id_size}) and password <<#{@tenant_password}>> (len = #{tenant_password_size}).")
        @socket.syswrite(["2#{@auth_frame_type}"].pack("A*"))
        @socket.syswrite([tenant_id_size].pack("C"))
        @socket.syswrite([@tenant_id].pack("A*"))
        @socket.syswrite([tenant_password_size].pack("C"))
        @socket.syswrite([@tenant_password].pack("A*"))
        @socket.flush()
  
        # Multi-tenant handshake - read response from server
        MTLumberjack.get_logger().info("Waiting for authorization ACK.", :host => @identification)
        ready = true
        response = ""
        if not @opts[:ibm_java]
          # We rely on select for timing out on read
          ready = IO.select([@socket], nil, nil, MTLumberjack::ACK_READ_TIMEOUT)
        end
        if ready
          response = @socket.sysread(6)
        else
          force_close()
          raise "Timed out while reading authorization ACK!"
        end
          
        MTLumberjack.get_logger().info("Authorization ACK received.", :host => @identification)
        MTLumberjack.get_logger().info("Response from the server: #{response}", :host => @identification)  
        ack = response.unpack("A*N")
        MTLumberjack.get_logger().info("ack = #{ack.inspect}", :host => @identification)
        if ack[0] == "0A"
          # Connection not authorized
          MTLumberjack.get_logger().error("Invalid tenant authorization. Please, check the tenant id and password!", :host => @identification)
          force_close()
          raise ArgumentError.new('Invalid tenant authorization. Please, check the tenant id and password!')
        end
        
      end
    end
    
    private 
    def non_blocking_ssl_connect(ssl_socket)
      begin
        ssl_socket.connect_nonblock()
      rescue IO::WaitWritable
        if IO.select(nil, [ssl_socket], nil, MTLumberjack::CONNECT_TIMEOUT)
          retry
        else
          raise "Connection timeout"
        end
      rescue IO::WaitReadable
        if IO.select([ssl_socket], nil, nil, MTLumberjack::CONNECT_TIMEOUT)
          retry
        else
          raise "Connection timeout"
        end
      end
    end
    
    def non_blocking_tcp_connect(socket, sockaddr)
      begin
        socket.connect_nonblock(sockaddr)
      rescue IO::WaitWritable
        if IO.select(nil, [socket], nil, MTLumberjack::CONNECT_TIMEOUT)
          begin
            socket.connect_nonblock(sockaddr)
          rescue Errno::EISCONN
          end
        else
          raise "Connection timeout"
        end
      rescue IO::WaitReadable
        if IO.select([socket], nil, nil, MTLumberjack::CONNECT_TIMEOUT)
          begin
            socket.connect_nonblock(sockaddr)
          rescue Errno::EISCONN
          end
        else
          raise "Connection timeout"
        end
      end
    end

    private 
    def force_close()
      if @opts[:ibm_java]
        begin
          @socket.sysclose()
        rescue
        end
      else
        begin
          @socket.close()
          @tcp_socket.close()
        rescue
        end
      end
    end

    private 
    def inc
      @sequence = 0 if @sequence+1 > MTLumberjack::SEQUENCE_MAX
      @sequence += 1
    end

#    private
#    def write(msg)
#      #@socket.syswrite(["1", "W", @window_size].pack("AAN"))
#      compress = Zlib::Deflate.deflate(msg)
#      MTLumberjack.get_logger().debug("Sending a compressed frame; size = #{compress.length}")
#      readfds, writefds, errorfds = select(nil, [@socket], nil)
#      p :r => readfds, :w => writefds, :e => errorfds
#      bytes_sent = @socket.syswrite(["1","C",compress.length,compress].pack("AANA#{compress.length}"))
#      MTLumberjack.get_logger().debug("Number of bytes actually sent = #{bytes_sent}")
#    end
#
#    public
#    def write_hash(hash)
#      MTLumberjack.get_logger().debug("Inside client.write_hash. Hash = #{hash}")
#      MTLumberjack.get_logger().debug("sequence = #{@sequence}; last_ack = #{@last_ack}; window_size = #{@window_size}")
#      frame = to_frame(augment_hash(hash), inc)
#      ack if (@sequence - (@last_ack + 1)) >= @window_size
#      write frame
#    end
    
    public 
    def write_events(events)
      frames_bytes = ""
      n_frames = 0
      events.each do |event|
        frames_bytes += to_frame(augment_hash(event), inc)
        n_frames += 1
      end
      if n_frames > 0
        begin
#          MTLumberjack.get_logger().debug("Will send a total of #{n_frames} data frames in one compressed frame.", :host => @identification)
#          compress = Zlib::Deflate.deflate(frames_bytes)
#          bytes_sent = 0
#          @socket_mutex.synchronize do
#            ready = IO.select(nil, [@socket], [@socket], MTLumberjack::WRITE_TIMEOUT)
#            if ready
#              if ready[2][0]
#                raise "Detected a network connection problem before sending data."
#              elsif ready[1][0]
#                # Send appropriate window size to server
#                @socket.syswrite(["1", "W", n_frames].pack("AAN"))
#                @socket.flush()
#                      
#                MTLumberjack.get_logger().debug("Sending a compressed frame; payload size = #{compress.length}", :host => @identification)
#                bytes_sent = @socket.syswrite(["1","C",compress.length,compress].pack("AANA#{compress.length}"))
#                @socket.flush()
#              end
#            else
#              raise "Timed out while sending data!"
#            end
#          end
#          MTLumberjack.get_logger().debug("Number of bytes actually sent (payload + header) = #{bytes_sent}", :host => @identification)
#          MTLumberjack.get_logger().debug("sequence = #{@sequence}; last_ack = #{@last_ack}; n_frames = #{n_frames}", :host => @identification)
          select_send_data(n_frames, frames_bytes)
          ack(n_frames)
          
        rescue => e
          MTLumberjack.get_logger().warn("Error while sending a compressed frame to the server. The connection was probably lost. Will reconnect and resend data",
            :exception => e,
            :backtrace => e.backtrace, 
            :host => @identification
          )
          @socket_mutex.synchronize do
              force_close()
          end
          
          # The connection was probably lost. 
          # We need to reconnect and make sure we send the events to the server.
          begin
            connect
          rescue => e
            MTLumberjack.get_logger().warn("Error reconnecting to the server while sending a compressed frame. Reconnecting...",
              :exception => e,
              :backtrace => e.backtrace,
              :host => @identification
            ) 
            sleep(5)
            retry
          end
          
          retry
        end
      end
    end
    
    private 
    def select_read_ack()
      ready = true
      if not @opts[:ibm_java]
        # We rely on select for timing out on read
        ready = IO.select([@socket], nil, nil, MTLumberjack::ACK_READ_TIMEOUT)
      end
      if ready
        version = @socket.sysread(1)
        MTLumberjack.get_logger().debug("Read ACK version = #{version}", :host => @identification)
        type = @socket.sysread(1)
        MTLumberjack.get_logger().debug("Read ACK type = #{type}", :host => @identification)
        raise "Whoa we shouldn't get this frame: #{type}" if type != "A"
        @last_ack = @socket.sysread(4).unpack("N").first
      else
        raise "Timed out while reading ACK!"
      end
    end
    
    private 
    def select_send_data(n_frames, frames_bytes)
      MTLumberjack.get_logger().debug("Will send a total of #{n_frames} data frames in one compressed frame.", :host => @identification)
      compress = Zlib::Deflate.deflate(frames_bytes)
      bytes_sent = 0
      @socket_mutex.synchronize do
        if @opts[:ibm_java]
          # Send appropriate window size to server
          @socket.syswrite(["1", "W", n_frames].pack("AAN"))
          @socket.flush()
                          
          MTLumberjack.get_logger().debug("Sending a compressed frame; payload size = #{compress.length}", :host => @identification)
          bytes_sent = @socket.syswrite(["1","C",compress.length,compress].pack("AANA#{compress.length}"))
          @socket.flush()
        else
          ready = IO.select(nil, [@socket], [@socket], MTLumberjack::WRITE_TIMEOUT)
          if ready
            if ready[2][0]
              raise "Detected a network connection problem before sending data."
            elsif ready[1][0]
              # Send appropriate window size to server
              @socket.syswrite(["1", "W", n_frames].pack("AAN"))
              @socket.flush()
                    
              MTLumberjack.get_logger().debug("Sending a compressed frame; payload size = #{compress.length}", :host => @identification)
              bytes_sent = @socket.syswrite(["1","C",compress.length,compress].pack("AANA#{compress.length}"))
              @socket.flush()
            end
          else
            raise "Timed out while sending data!"
          end
        end
      end
      MTLumberjack.get_logger().debug("Number of bytes actually sent (payload + header) = #{bytes_sent}", :host => @identification)
      MTLumberjack.get_logger().debug("sequence = #{@sequence}; last_ack = #{@last_ack}; n_frames = #{n_frames}", :host => @identification)
    end
    
    private 
    def augment_hash(hash)
        new_hash = {}
        if hash.has_key?('line') 
          begin
            # Check if we have been configured to use the json codec. If not, the following line will raise an exception. 
            payload_hash = JSON.parse(hash['line']) 
              
            # If we get here, we have been configured to use the json codec, allowing us preserve all information
            #contained in the event data structure (i.e., all semantically rich annotations that make log searching more 
            #powerful. 
            MTLumberjack.get_logger().debug("Hash parsed by client.augment_hash = #{payload_hash}", :host => @identification)
            # Add event attributes to the hash that will be shipped as a frame
            payload_hash.each do |k, v|
              if k == MTLumberjack::LS_TIMESTAMP
                # This is needed to prevent the mtlumberjack server from dropping our event.
                # @timestamp will be received as a String by mtlumberjack, but the server's Logstash agent is expecting a Time class.
                # This trick will prevent such a conflict, while guaranteeing that we can preserve our own timestamp.
                # I conjecture that, if the mtlumberjack server had been configured to use the json codec (which it is not), 
                # then this trick would not be needed.
                new_hash[MTLumberjack::LB_TIMESTAMP] = v
              else
                new_hash[k] = v
              end
            end
            MTLumberjack.get_logger().debug("New hash derived from parsed hash = #{new_hash}", :host => @identification)
            # Make sure the 'line' attribute is overwritten with the actual log message
            MTLumberjack.get_logger().debug("payload_hash['message'] = #{payload_hash['message']}", :host => @identification)
            new_hash['line'] = payload_hash['message'] if payload_hash.has_key?('message')
            MTLumberjack.get_logger().debug("New hash after adjusting line attribute = #{new_hash}", :host => @identification)
          rescue JSON::ParserError => je
            # Either the json codec was not used, or something strange happened
            MTLumberjack.get_logger().debug("mtlumberjack could not parse JSON from payload. The JSON codec plugin was probably not being used--> << #{hash['line']} >>", :host => @identification)
            new_hash.merge!(hash)
          end
        end
        if @auth_frame_type == "T"
          # The code is running in 'regular mode', i.e., no introspection is taking place.
          # We have been given a regular tenant id.
          new_hash.merge!(
             MTLumberjack::ALCHEMY_TENANT_ID_KEY => @tenant_id
             #'host' => @my_ip
             #'file' => new_hash['path'] # Just because this attribute is expected by the current OpVis dashboard 
          )
        else
          # The code is running in 'introspection mode' and we have been given a supertenant id. 
          # Thus, we need to adjust the value of the 'path' attribute. The current path value 
          #is relative to the host filesystem. We need to make it relative to the 
          #container filesystem and extract from it the actual tenant id on behalf of which we will emit the
          #log event.
          MTLumberjack.get_logger().debug("mtlumberjack is running in introspection mode. Need to adjust 'path'.", :host => @identification)
          if new_hash.has_key?('path')
             MTLumberjack.get_logger().debug("Found 'path' in the event.", :host => @identification)
             /#{MTLumberjack::INTROSPECTION_HOST_BASE_DIR}\/(.*?)\/(.*?)\/(.*?)\/(.*)$/.match(new_hash['path']) do |m|
                MTLumberjack.get_logger().debug("Matched 'path'. Now, making it relative to the container filesystem.", :host => @identification)
                tenant_id = m[1]
                group_id = m[2]
                instance_id = m[3]
                container_file_path = "/#{m[4]}"
                new_hash.merge!(
                  MTLumberjack::ALCHEMY_TENANT_ID_KEY => tenant_id,
                  MTLumberjack::GROUP_ID_KEY => group_id,
                  MTLumberjack::INSTANCE_ID_KEY => instance_id,
                  'path' => container_file_path
                  #'file' => container_file_path # Just because this attribute is expected by the current OpVis dashboard
                )
             end 
          end
        end
         
        return new_hash
    end

    private
    def ack(last_n_frames)
      MTLumberjack.get_logger().debug("Waiting for ACK from server...", :host => @identification)
      @socket_mutex.synchronize do
#        ready = IO.select([@socket], nil, nil, MTLumberjack::ACK_READ_TIMEOUT)
#        if ready
#          version = @socket.sysread(1)
#          MTLumberjack.get_logger().debug("Read ACK version = #{version}", :host => @identification)
#          type = @socket.sysread(1)
#          MTLumberjack.get_logger().debug("Read ACK type = #{type}", :host => @identification)
#          raise "Whoa we shouldn't get this frame: #{type}" if type != "A"
#          @last_ack = @socket.sysread(4).unpack("N").first
#        else
#          raise "Timed out while reading ACK!"
#        end
         select_read_ack()
      end
      MTLumberjack.get_logger().debug("Received ACK from server. last_ack = #{@last_ack}; last_n_frames = #{last_n_frames}", :host => @identification)
      #ack if (@sequence - (@last_ack + 1)) >= @window_size
      #ack if (@sequence - (@last_ack + 1)) >= last_n_frames
    end

    private
    def to_frame(hash, sequence)
      MTLumberjack.get_logger().debug("Augmented hash = #{hash.inspect}", :host => @identification)
      frame = ["1", "D", sequence]
      pack = "AAN"
      keys = deep_keys(hash)
      frame << keys.length
      pack << "N"
      keys.each do |k|
        val = deep_get(hash,k)
        key_length = k.length
        val_length = val.length
        frame << key_length
        pack << "N"
        frame << k
        pack << "A#{key_length}"
        frame << val_length
        pack << "N"
        frame << val
        pack << "A#{val_length}"
      end
      
      MTLumberjack.get_logger().debug("F R A M E being packed: #{frame}", :host => @identification)
      frame.pack(pack)
    end

    private
    def deep_get(hash, key="")
      return hash if key.nil? and hash.class == String
      return hash.join(',') if key.nil? and hash.class == Array
      deep_get(
        hash[key.split('.').first],
        key[key.split('.').first.length+1..key.length]
      )
    end

    private
    def deep_keys(hash, prefix="")
      keys = []
      hash.each do |k,v|
        keys << "#{prefix}#{k}" if v.class == String or v.class == Array
        keys << deep_keys(hash[k], "#{k}.") if v.class == Hash
      end
      keys.flatten
    end
  end
end
