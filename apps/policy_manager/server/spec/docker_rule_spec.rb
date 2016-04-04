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
    begin
      SentinelDocker::Store.indices.create index: 'testing'
    rescue
      puts 'Index not created. Already existed.'
    end
    SentinelDocker::Config.db.index_name = 'testing'

    SentinelDocker::Models.constants.each do |model|
      #    next if model == :Base || model == :RuleAssign
      next if model == :Base
      model = SentinelDocker::Models.const_get(model)
      model.do_mapping

    end

  end

  it 'will create new container' do

    image = {image_id: "image1", image_name: "image1", created: Time.now.to_i, created_by: "ls -al", created_from: "image0"}
    post 'api/images', image.to_json, 'CONTENT_TYPE' => 'application/json'   
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['image_id']).to eql(image[:image_id])
    expect(JSON.parse(last_response.body)['image_name']).to eql(image[:image_name])
    expect(JSON.parse(last_response.body)['created']).to eql(image[:created])
    expect(JSON.parse(last_response.body)['created_by']).to eql(image[:created_by])
    expect(JSON.parse(last_response.body)['created_from']).to eql(image[:created_from])

  end

  it 'will create new container' do
    get 'api/images'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    image_id = JSON.parse((body[0]).to_json)['id']

    containers = []
    (0...10).each do |i|
      containers << {container_id: "container#{i}", container_name: "container#{i}", image_id: image_id, created: "1000#{i}"}
    end

    post 'api/containers', containers[0].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['container_name']).to eql(containers[0][:container_name])
    expect(JSON.parse(last_response.body)['container_id']).to eql(containers[0][:container_id])
    expect(JSON.parse(last_response.body)['image_id']).to eql(containers[0][:image_id])
    expect(JSON.parse(last_response.body)['created']).to eql(containers[0][:created])

    post 'api/containers', containers[1..10].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to be(9)

  end


  it 'will return a JSON array of containers' do
    get 'api/containers'
    expect(last_response.ok?).to be(true)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to be(10)
  end

  it 'will update a container with put' do
    get 'api/containers'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    put 'api/containers/' + id_1, { host_id: 'host1', created: '1100'}.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(200)
    get 'api/containers/' + id_1
    body = JSON.parse(last_response.body)
    expect(body['host_id']).to eql('host1')
    expect(body['created']).to eql('1100')
    # will return 400 as body is not passed
    put 'api/containers/' + id_1
    expect(last_response.status).to eql(400)
  end


  it 'will delete a container with a given id' do
    get 'api/containers'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    delete 'api/containers/' + id_1
    expect(last_response.status).to eql(204)
    # passing a wrong container groupid
    id_1 = 'incorrect1234'
    delete 'api/containers/' + id_1
    expect(last_response.status).to eql(404)
  end

  it 'will assign new container rule' do
    docker_container_id = "container10"
    post 'api/containers', {container_id: docker_container_id, container_name: "container10", image_id: "image10", created: "100010"}.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    container_id = JSON.parse(last_response.body)['id']
    expect(container_id).not_to be_nil

    container_rules = []
    (0...10).each do |i|
      post 'api/rules', {name: "rule#{i}"}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eql(201)
      rule_id = JSON.parse(last_response.body)['id']
      expect(rule_id).not_to be_nil
      post 'api/rule_assign_defs', {rule_id: rule_id}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eql(201)
      rule_assign_def_id = JSON.parse(last_response.body)['id']
      expect(rule_assign_def_id).not_to be_nil
      container_rules << {container_id: container_id, rule_assign_def_id: rule_assign_def_id}
    end

    container_rule_ids = []
    (0...10).each do |i|
      post 'api/containers/'+container_id+'/rules', container_rules[i].to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eql(201)
      expect(JSON.parse(last_response.body)['container_id']).to eql(container_rules[i][:container_id])
      expect(JSON.parse(last_response.body)['rule_assign_def_id']).to eql(container_rules[i][:rule_assign_def_id])
      container_rule_ids << JSON.parse(last_response.body)['id']
    end

  end

  it 'will get container rule' do
    #get container
    get 'api/containers'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    docker_container_id = "container10"
    container_id = nil
    body.each do |b|
      c = JSON.parse(b.to_json)
      container_id = c['id'] if c['container_id']==docker_container_id
    end

    #get rules
    get 'api/containers/'+container_id+'/rules'
    expect(last_response.ok?).to be(true)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to be(10)
    body.each do |b|
      get 'api/containers/'+container_id+'/rules/'+b['id']
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['container_id']).to eql(container_id)
    end

  end

  it 'will put container rule' do
    #get container
    get 'api/containers'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    docker_container_id = "container10"
    container_id = nil
    body.each do |b|
      c = JSON.parse(b.to_json)
      container_id = c['id'] if c['container_id']==docker_container_id
    end

    get 'api/containers/'+container_id+'/rules'
    expect(last_response.ok?).to be(true)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to be(10)
    body.each do |b|
      container_rule_id = b['id']
      b['ignore_failure'] = true
      b['ignore_justification'] = 'sorry'
      put 'api/containers/'+container_id+'/rules/'+container_rule_id, b.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eql(200)
      get 'api/containers/'+container_id+'/rules/'+b['id']
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['container_id']).to eql(container_id)
      expect(JSON.parse(last_response.body)['ignore_failure']).to eql(true)

      put 'api/containers/'+container_id+'/rules/'+container_rule_id, "xxxxxx", 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eql(400)

      put 'api/containers/'+container_id+'/rules/dammy_id', b.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eql(404)
    end
  end


  it 'will run rule on containers' do
    #get container
    get 'api/containers'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    docker_container_id = "container10"
    container_id = nil
    body.each do |b|
      c = JSON.parse(b.to_json)
      container_id = c['id'] if c['container_id']==docker_container_id
    end

    #run container_rule
    get 'api/containers/'+container_id+'/rules'
    expect(last_response.ok?).to be(true)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to be(10)

    body.each do |b|
      container_rule_id = b['id']
      #1st run
      get "api/containers/#{container_id}/rules/#{container_rule_id}/run"
      expect(last_response.status).to eql(200)
      #puts JSON.parse(last_response.body)

      get "api/containers/#{container_id}/rules/#{container_rule_id}/runs"
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)).to be_a(Array)
      run_size = JSON.parse(last_response.body).size
      #puts "run_size=#{run_size}"

      #2nd run
      get "api/containers/#{container_id}/rules/#{container_rule_id}/run"
      expect(last_response.status).to eql(200)
      #puts JSON.parse(last_response.body)

      get "api/containers/#{container_id}/rules/#{container_rule_id}/runs"
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)).to be_a(Array)
      expect(JSON.parse(last_response.body).size).to be(run_size+1)

    end

    #bulk run
    get 'api/containers/'+container_id+'/run'
    expect(last_response.ok?).to be(true)
    expect(JSON.parse(last_response.body)).to be_a(Array)

    runs = JSON.parse(last_response.body)
    runs.each do |each_run|
      container_rule_id = each_run['container_rule_id']

      get "api/containers/#{container_id}/rules/#{container_rule_id}/runs"
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)).to be_a(Array)
      expect(JSON.parse(last_response.body).first['timestamp']).to eq(each_run['timestamp'])
    end

  end

  it 'will delete container rule' do

    #get container
    get 'api/containers'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    docker_container_id = "container10"
    container_id = nil
    body.each do |b|
      c = JSON.parse(b.to_json)
      container_id = c['id'] if c['container_id']==docker_container_id
    end

    #delete rule
    get 'api/containers/'+container_id+'/rules'
    expect(last_response.ok?).to be(true)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to be(10)
    body.each do |b|
      container_rule_id = b['id']
      delete 'api/containers/'+container_id+'/rules/dammy_id'
      expect(last_response.status).to eql(404)

      get 'api/containers/'+container_id+'/rules/'+container_rule_id
      expect(last_response.status).to eql(200)

      delete 'api/containers/'+container_id+'/rules/'+container_rule_id
      expect(last_response.status).to eql(204)

      get 'api/containers/'+container_id+'/rules/'+container_rule_id
      expect(last_response.status).to eql(404)
    end

  end

  after :all do
    SentinelDocker::Store.indices.delete index: 'testing'
  end
end
