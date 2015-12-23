require 'hashie'
require 'logger'
require 'elasticsearch'
require 'net/https'
require 'uri'

module SentinelDocker
  module ServerAdmin

    CS_HOST = 'cloudsight.sl.cloud9.ibm.com'
    CS_PORT = 8885
    CS_ES_HOST = 'elastic2-cs.sl.cloud9.ibm.com'
    CS_ES_PORT = 9200
    CS_ES_MAX_RETURN = 1000
    CloudSightStore = Elasticsearch::Client.new(hosts: [{ host: "#{CS_ES_HOST}", port: "#{CS_ES_PORT}" }], log: false)
    CloudSightService = Elasticsearch::Client.new(hosts: [{ host: "#{CS_ES_HOST}", port: "#{CS_ES_PORT}" }], log: false)

  	def search_service(api, params = nil)
      uri = URI.parse("http://#{CS_HOST}:#{CS_PORT}/api")
      uri.query = URI.encode_www_form(params) if params
      res = Net::HTTP.get_response(uri)
      body = Hashie::Mash.new(JSON.parse(res.body))
  	end

  	def do_query(index, type, body)
  	  param = {
        index: index,
        type: type.to_s,
        body: body
      }
      response = Hashie::Mash.new(Local_Store.search(param))
      results = response.hits.hits
  	end

    # CS_HOST = 'demo3.sl.cloud9.ibm.com'
    # CS_PORT = '9200'


    # num of requests 
    # curl -k -XGET http://elasticsearch:9200/local_jobs/requests/_count
    # num of runnings
    # curl -k -XGET http://elasticsearch:9200/local_jobs/running/_count
    
  end
end