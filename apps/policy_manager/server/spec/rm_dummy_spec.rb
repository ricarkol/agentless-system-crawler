# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require_relative 'support/coverage'
require 'sentinel-docker'
require 'rack/test'
require 'json'

include SentinelDocker::Models

RSpec.configure do |config|
  config.include Rack::Test::Methods
end

describe SentinelDocker::API do

  subject { SentinelDocker::API::Root }

  def app
    subject
  end

  before :all do
    SentinelDocker::Config.db.index_name = 'testing'
  end


  # before :all do
  #   begin
  #     SentinelDocker::Store.indices.create index: 'api_testing'
  #   rescue
  #     puts 'Index not created. Already existed.'
  #   end
  #   SentinelDocker::Config.db.index_name = 'api_testing'
  # end

  it 'will return a JSON array on resource collections' do
    get 'api/services/get_image_status_per_tenant', {}, 'rack.session' => {'identity' => 'ibm_admin'}
    body = JSON.parse(last_response.body)
    puts "response=#{JSON.pretty_generate(last_response.body)}"
    expect(last_response.ok?).to be(true)

    expect(body).to be_a(Array)
  end


  # after :all do
  #   SentinelDocker::Store.indices.delete index: 'testing'
  # end
end
