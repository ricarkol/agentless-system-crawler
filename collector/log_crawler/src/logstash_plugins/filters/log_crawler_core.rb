require 'logstash/filters/base'
require 'logstash/namespace'
require 'json'

class LogStash::Filters::LogCrawlerCore < LogStash::Filters::Base
  config_name "log_crawler_core"
  milestone 1
  
  # Base directory on the host to which the log crawler will map container's log files
  INTROSPECTION_HOST_BASE_DIR = '/var/log/crawler_container_logs'
  
  # Per-tenant config file containing type information for monitored log files 
  TYPE_MAPPING_FILE_NAME = 'd464347c-3b99-11e5-b0e9-062dcffc249f.type-mapping'
  
  # Maximum number of times we will attempt to open a type-mapping file 
  MAX_ATTEMPTS = 20
  
  public 
  
  def register
  end
  
  def filter(event)
    return unless filter?(event)
    
    if !event.include?('path')
      @logger.warn("Event #{event} has no path information. The type-mapping file will not be taken into account.")
      return
    end
    
    host_logfile_path = event['path']
    /#{INTROSPECTION_HOST_BASE_DIR}\/(.*?)\/(.*?)\/(.*?)\/(.*)$/.match(host_logfile_path) do |m|
      tenant_id = m[1]
      group_id = m[2]
      instance_id = m[3]
      container_file_path = "/#{m[4]}"
      
      n_retries = 0
      tenant_type_mapping_file_path = "#{INTROSPECTION_HOST_BASE_DIR}/#{tenant_id}/#{TYPE_MAPPING_FILE_NAME}"
      begin
          type_mapping_json = File.read(tenant_type_mapping_file_path)
          if type_mapping_json == ""
            # We have an empty type-mapping file. No type info has been given to us.
            @logger.debug("Empty type-mapping file #{tenant_type_mapping_file_path}; nothing to do.")
            return
          end
          begin
            type_mapping_hash = JSON.parse(type_mapping_json)
            if !type_mapping_hash.has_key?('log_files')
              @logger.warning("The type-mapping file #{tenant_type_mapping_file_path} has an unexpected format; ignoring it.")
              return
            end
            
            # Iterate over type mappings for this tenant to look for a type match for this Logstash event
            type_mapping_hash['log_files'].each do |mapping|
              if !mapping.has_key?('type') or !mapping.has_key?('name')
                @logger.warning("Ignoring type-mapping file #{tenant_type_mapping_file_path} due to missing information.")
              else
                @logger.debug("Trying to match container log file '#{container_file_path}' with type-mapping pattern '#{mapping['name']}'")
                if file_match(mapping['name'], container_file_path)
                  # We found a match for the log file corresponding to this Logstash event
                  @logger.debug("Found a match in type-mapping file #{tenant_type_mapping_file_path}: mapping = #{mapping['name']}; container_log_file = #{container_file_path}")
                  if mapping['type'].nil?
                    # The type-mapping file contains the null type.
                    @logger.debug("Setting 'plain' type, since type-mapping file #{tenant_type_mapping_file_path} does not specify it: container_log_file = #{container_file_path}")
                    event['type'] = 'plain' 
                  else
                    @logger.debug("Setting type from type-mapping file #{tenant_type_mapping_file_path}: type = #{mapping['type']}; container_log_file = #{container_file_path}")
                    event['type'] = mapping['type']
                  end
                  return
                end
              end 
            end
          rescue => e
            @logger.error("Error while processing type-mapping file '#{tenant_type_mapping_file_path}'.", 
              :e => e, :backtrace => e.backtrace)
          end
      rescue => e
        if n_retries >= MAX_ATTEMPTS
          @logger.error("Unable to read type-mapping file '#{tenant_type_mapping_file_path}' after #{n_retries} attempts. Giving up!")
          return
        end
        sleep(3)
        n_retries += 1
        @logger.warn("Retrying to read type-mapping file '#{tenant_type_mapping_file_path}'. Number of attempts so far: #{n_retries}")
        retry
      end
    end
  end
  
  private
  
  # Check if a given pattern matches a given file path. 
  # The current code does not support regex. We will support it in a future version. 
  # In a future version, the parameter pattern will be a regex. 
  # 
  # Parameters:
  #  - pattern (string): Pattern we want to check against the file path
  #  - file_path (string): File path under consideration
  def file_match(pattern, file_path)
    return pattern == file_path
  end
end