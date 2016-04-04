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
      SentinelDocker::Store.indices.create index: 'api_testing'
    rescue
      puts 'Index not created. Already existed.'
    end
    SentinelDocker::Config.db.index_name = 'api_testing'
  end

  it 'will return a JSON array on resource collections' do
    get 'api/rules'
    expect(last_response.ok?).to be(true)

    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
  end

  it 'will return items according to a "Range: items=n-m" header' do
    (0...10).each do |i|
      c = Container.new(container_id: "container#{i}", container_name: "container#{i}", image_id: "image#{i}", created: "1000#{i}")
      expect(c.save).to be(true)
    end

    get 'api/containers'
    expect(last_response.ok?).to be(true)

    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to be(10)

    content_range = last_response.headers['Content-Range']
    expect(content_range).to be_a(String)
    expect(content_range).to eq('items 1-10/10')

    header 'Range', 'items=5-9'
    get 'api/containers'
    expect(last_response.status).to be(206)
    body = JSON.parse(last_response.body)
    expect(body.size).to be(5)
  end

  it 'will return a "Content-Range: items n-m/total" header' do
    get 'api/containers'
    content_range = last_response.headers['Content-Range']
    expect(content_range).to be_a(String)
    expect(content_range).to eq('items 1-10/10')

    header 'Range', 'items=5-9'
    get 'api/containers'
    content_range = last_response.headers['Content-Range']
    expect(content_range).to eq('items 5-9/10')
  end

  # testing blocks for container groups
  it 'will create a rule group given a name' do
    post 'api/rule_groups', { name: 'mytestgroup1' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup1')
    # passing name and description
    post 'api/container_groups', { name: 'containerGroup2', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('containerGroup2')
    expect(JSON.parse(last_response.body)['description']).to eql('Hello putting some description')
    post 'api/container_groups', { name: 'containerGroup3', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('containerGroup3')
    # will create a container group given a name ,description and id
    post 'api/container_groups', { id: '100', name: 'containerGroup4', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('containerGroup4')
    # will not create a container rule as name is not sent
    post 'api/container_groups', { id: '100', name: ' ', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(400)
  end

  it 'will list the container groups' do
    get 'api/container_groups'
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to eql(3)
    # will fetch a container group with a range
    header 'Range', 'items=2-3'
    get 'api/container_groups'
    expect(last_response.status).to eql(206)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
  end

  it 'will update a container group with put' do
    get 'api/container_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    put 'api/container_groups/' + id_1, { id: '100', name: 'containerGroupModified1', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(200)
    # will return 400 as body is not passed
    put 'api/container_groups/' + id_1
    expect(last_response.status).to eql(400)
  end

  it 'will show a container group with a given id' do
    get 'api/container_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    get 'api/container_groups/' + id_1
    expect(last_response.status).to eql(200)
    # passing an incorrect id
    id_1 = 'incorrect123'
    get 'api/container_groups/' + id_1
    expect(last_response.status).to eql(404)
  end

  it 'will delete a container group with a given id' do
    get 'api/container_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    delete 'api/container_groups/' + id_1
    expect(last_response.status).to eql(204)
    # passing a wrong container groupid
    id_1 = 'incorrect1234'
    delete 'api/container_groups/' + id_1
    expect(last_response.status).to eql(404)
  end

  it 'will apply rule_group(s) to a container_group post api' do
    # using get method of container group to get a valid container_group id
    get 'api/container_groups'
    body = JSON.parse(last_response.body)
    require 'pp'
    id_1 = JSON.parse((body[1]).to_json)['id']
    # using get method of rule group to get a valid rule_group id
    get 'api/rule_groups'
    p_body = JSON.parse(last_response.body)
    id_2 = JSON.parse((p_body[0]).to_json)['id']
    # passing valid container_group id and rule_group id array
    post 'api/container_groups/' + id_1, [id_2].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(204)
    # passing invalid container_group id and valid rule_group id array
    post 'api/container_groups/' + 'we345678', [id_2].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(404)
    # passing empty array in body
    post 'api/container_groups/' + id_1 , [].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(400)
    # passing empty  body
    post 'api/container_groups/' + id_1
    expect(last_response.status).to eql(400)
  end

  it 'will add a container(s) to a container group' do
    # get container group id
    get 'api/container_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[0]).to_json)['id']
    # getting 2 valid container ids
    get 'api/containers'
    body_sys = JSON.parse(last_response.body)
    container_id = JSON.parse((body_sys[0]).to_json)['id']
    container_id1 = JSON.parse((body_sys[1]).to_json)['id']
    # passing correct params
    post 'api/container_groups/' + id_1 + '/members', [container_id, container_id1].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(204)
    # passing invalid containerGroup id
    id_2 = '0oi8u7'
    post 'api/container_groups/' + id_1 + '/members', [id_2].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(400)
    # passing invalid container group id
    get 'api/container_groups/12345tygh/members'
    expect(last_response.status).to eql(404)
  end

  it 'will list the container group members' do
    get 'api/container_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[0]).to_json)['id']
    # passing correct parameters
    get 'api/container_groups/' + id_1 + '/members'
    expect(last_response.status).to eql(200)
    # passing invalid container group id
    get 'api/container_groups/12345tygh/members'
    expect(last_response.status).to eql(404)
  end

  it 'will remove a container from a container group' do
    # get container group id
    get 'api/container_groups'
    body = JSON.parse(last_response.body)
    # this id has containers as we have added a container in the above block
    id_1 = JSON.parse((body[0]).to_json)['id']
    # passing correct params
    get 'api/container_groups/' + id_1 + '/members'
    require 'pp'
    container_body = JSON.parse(last_response.body)
    container_id = JSON.parse((container_body[0]).to_json)['id']
    # passing all valid parameters for DELETE api
    delete 'api/container_groups/' + id_1 + '/members/' + container_id
    expect(last_response.status).to eql(204)
    # passing incorrect container group id
    delete 'api/container_groups/IamIncorrectId/members/' + container_id
    expect(last_response.status).to eql(404)
    # passing incorrect container id
    delete 'api/container_groups/' + id_1 + '/members/InCorrectContainerId'
    expect(last_response.status).to eql(400)
  end

  # it 'will show compliance level of a container group' do
  #   # get container group id
  #   get 'api/container_groups'
  #   body = JSON.parse(last_response.body)
  #   expect(body).to be_a(Array)
  #   # this id has containers as we have added a container in the above block
  #   id_1 = JSON.parse((body[0]).to_json)['id']
  #   get 'api/container_groups/' + id_1 + '/compliance'
  #   expect(last_response.status).to eql(200)
  #   # passing incorrect container group id
  #   id_1 = '12345'
  #   get 'api/container_groups/' + id_1 + '/compliance'
  #   expect(last_response.status).to eql(404)
  # end

  it 'will create a user  given an identity' do
    post 'api/users', { identity: '12345678', fullname: 'Bhairavi' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['fullname']).to eql('Bhairavi')
    # not passing the mandatory field identity
    post 'api/users', { fullname: 'Bhairavi' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(400)
  end

  it 'will list the users' do
    get 'api/users'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(last_response.status).to eql(200)
  end

  it 'will update a user' do
    get 'api/users'
    body = JSON.parse(last_response.body)
    id_1 = JSON.parse((body[0]).to_json)['id']
    identity1 = JSON.parse((body[0]).to_json)['identity']
    put 'api/users/' + id_1, { identity: identity1, fullname: 'Bhairavi Konwar' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(JSON.parse(last_response.body)['fullname']).to eql('Bhairavi Konwar')
    expect(last_response.status).to eql(200)
    # passing wrong id
    put 'api/users/abc', { identity: identity1, fullname: 'Bhairavi Konwar' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(404)
  end

  it 'will show a user given an id ' do
    get 'api/users'
    body = JSON.parse(last_response.body)
    id_1 = JSON.parse((body[0]).to_json)['id']
    get 'api/users/' + id_1
    expect(last_response.status).to eql(200)
    # passing wrong id
    get 'api/users/abc'
    expect(last_response.status).to eql(404)
  end

  it 'will delete a user given an id ' do
    get 'api/users'
    body = JSON.parse(last_response.body)
    id_1 = JSON.parse((body[0]).to_json)['id']
    delete 'api/users/' + id_1
    expect(last_response.status).to eql(204)
    # passing wrong id
    delete 'api/users/abc'
    expect(last_response.status).to eql(404)
  end


  # Tests for rule_groups APIs

  # 1. Tests for POST API i.e. post /api/rule_groups

  it 'will create a new rule group given a name' do
    post '/api/rule_groups', { name: 'mytestgroup' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup')

    post '/api/rule_groups', { name: 'mytestgroup1' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup1')

    post '/api/rule_groups', { name: 'mytestgroup2' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup2')

    post '/api/rule_groups'
    expect(last_response.status).to eql(400)

  end

  # 2. Tests for GET API i.e. get /api/rule_groups

  it 'will list the rule groups' do
    get '/api/rule_groups'
    expect(last_response.status).to eql(200)
  end

  it 'will return a rule group with a range' do
    header 'Range', 'items=1-2'
    get '/api/rule_groups'
    expect(last_response.status).to eql(206)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
  end

  # 3. Tests for PUT API i.e. put /api/rule_groups/{id}

  it 'will update a rule group with provided id' do
    get '/api/rule_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']

    rule_group = SentinelDocker::Models::RuleGroup.new(name: 'rule group1')
    rule_group.save

    put '/api/rule_groups/' + id_1, { name: 'Updated_Rule_Name' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)['name']).to eql('Updated_Rule_Name')

    put '/api/rule_groups/' + id_1, { name: 'Updated_Rule_Name' }.to_json
    expect(last_response.status).to eql(400)

    put '/api/rule_groups/xyz', { name: 'Updated_Rule_Name' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(404)

  end

  # 4. Tests for GET API i.e. get /api/rule_groups/{id}

  it 'will return a rule group with provided id' do
    get '/api/rule_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    rule_name_1 = JSON.parse((body[1]).to_json)['name']

    get '/api/rule_groups/' + id_1
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)['name']).to eql(rule_name_1)

    get '/api/rule_groups/xyz'
    expect(last_response.status).to eql(404)

  end

  # 5. Tests for DELETE API i.e. delete /api/rule_groups/{id}

  it 'will delete a rule group with provided id' do
    get '/api/rule_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    size = body.size

    delete '/api/rule_groups/xyz'
    expect(last_response.status).to eql(404)
    get '/api/rule_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to eql(size)

    delete '/api/rule_groups/' + id_1
    expect(last_response.status).to eql(204)
    get '/api/rule_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to eql(size - 1)

  end

  # 6. Tests for GET API i.e. get /api/rule_groups/{id}/members
  it 'will list the rule group members of given id' do
    get '/api/rule_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']

    get '/api/rule_groups/' + id_1 + '/members'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)

    get '/api/rule_groups/xyz/members'
    expect(last_response.status).to eql(404)

  end

  # 7. Tests for POST API i.e. post/rule_group/{id}/members
  it 'will add rules to the rule group with given id' do
    get '/api/rule_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[0]).to_json)['id']

    rule_1 = SentinelDocker::Models::Rule.new(name: 'Rule_test1')
    rule_1.save
    id_4 = rule_1.id
    rule_2 = SentinelDocker::Models::Rule.new(name: 'Rule_test2')
    rule_2.save
    rule_3 = SentinelDocker::Models::Rule.new(name: 'Rule_test3')
    rule_3.save

    post '/api/rule_groups/' + id_1 + '/members', [id_4].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(204)

    # bad request with invalid rule_id array
    post '/api/rule_groups/' + id_1 + '/members', ['id5'].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(400)

    post '/api/rule_groups/xyz/members' , [id_4].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(404)

  end

  # 8. Tests for DELETE API i.e. delete /api/rule_groups/{id}/members/{rule_id}
  it 'will delete rule with rule id from rule group' do

    get '/api/rule_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[0]).to_json)['id']

    get '/api/rule_groups/' + id_1 + '/members'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    rule_id = JSON.parse((body[0]).to_json)['id']

    delete '/api/rule_groups/' + id_1 + '/members/' + rule_id
    expect(last_response.status).to eql(204)

    delete '/api/rule_groups/' + id_1 + '/members/xyz'
    expect(last_response.status).to eql(400)

    delete '/api/rule_groups/xyz/members/abc'
    expect(last_response.status).to eql(404)

  end

  # Tests for rules APIS
  # 1. Test for GET API i.e. get /api/rules
  it 'will give the list of rules' do

    get '/api/rules'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(last_response.status).to eql(200)

  end

  it 'will return a rules given a range' do

    header 'Range', 'items=1-2'
    get '/api/rules'
    expect(last_response.status).to eql(206)

  end

  # 2. Test for PUT API i.e. put /api/rules/{id}
  it 'will update the rule given an id' do

    get '/api/rules'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    rule_id = JSON.parse((body[0]).to_json)['id']

    put '/api/rules/' + rule_id, { grace_period: 30 }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)['grace_period']).to eql(30)

    put '/api/rules/' + rule_id, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(400)

    put '/api/rules/xyz', { description: 'rule_updated' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(404)
  end

  # 3. Test for GET API i.e. /api/rules/{id}
  it 'will return polict given an id' do
    rule_5 = SentinelDocker::Models::Rule.new(name: 'Rule_test5')
    rule_5.save

    get '/api/rules/' + rule_5.id
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)['name']).to eql('Rule_test5')

    get '/api/rules/xyz'
    expect(last_response.status).to eql(404)
  end

  # 4. Test for GET API i.e. /api/rules/{id}/parameters
  it 'will return polict given an id' do
    rule_6 = SentinelDocker::Models::Rule.new(name: 'Rule_test6', description: 'This is test rule')
    rule_6.save

    get '/api/rules/' + rule_6.id + '/parameters'
    expect(last_response.status).to eql(200)

    get '/api/rules/xyz/parameters'
    expect(last_response.status).to eql(404)

  end

  after :all do
    SentinelDocker::Store.indices.delete index: 'testing'
  end
end
