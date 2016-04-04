# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require_relative 'support/coverage'
require 'sentinel'
require 'rack/test'
require 'json'

include Sentinel::Models

RSpec.configure do |config|
  config.include Rack::Test::Methods
end

describe Sentinel::API do

  subject { Sentinel::API::Root }

  def app
    subject
  end

  before :all do
    begin
      Sentinel::Store.indices.create index: 'testing'
    rescue
      puts 'Index not created. Already existed.'
    end
    Sentinel::Config.db.index_name = 'testing'
  end

  it 'will return a JSON array on resource collections' do
    get 'api/policies'
    expect(last_response.ok?).to be(true)

    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
  end

  it 'will return items according to a "Range: items=n-m" header' do
    (0...10).each do |i|
      expect(System.new(ip: "10.10.10.#{i}").save).to be(true)
    end

    get 'api/systems'
    expect(last_response.ok?).to be(true)

    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to be(10)

    content_range = last_response.headers['Content-Range']
    expect(content_range).to be_a(String)
    expect(content_range).to eq('items 1-10/10')

    header 'Range', 'items=5-9'
    get 'api/systems'
    expect(last_response.status).to be(206)
    body = JSON.parse(last_response.body)
    expect(body.size).to be(5)
  end

  it 'will return a "Content-Range: items n-m/total" header' do
    get 'api/systems'
    content_range = last_response.headers['Content-Range']
    expect(content_range).to be_a(String)
    expect(content_range).to eq('items 1-10/10')

    header 'Range', 'items=5-9'
    get 'api/systems'
    content_range = last_response.headers['Content-Range']
    expect(content_range).to eq('items 5-9/10')
  end

  # testing blocks for system groups
  it 'will create a policy group given a name' do
    post 'api/policy_groups', { name: 'mytestgroup1' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup1')
    # passing name and description
    post 'api/system_groups', { name: 'systemGroup2', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('systemGroup2')
    expect(JSON.parse(last_response.body)['description']).to eql('Hello putting some description')
    post 'api/system_groups', { name: 'systemGroup3', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('systemGroup3')
    # will create a system group given a name ,description and id
    post 'api/system_groups', { id: '100', name: 'systemGroup4', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('systemGroup4')
    # will not create a system policy as name is not sent
    post 'api/system_groups', { id: '100', name: ' ', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(400)
  end

  it 'will list the system groups' do
    get 'api/system_groups'
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to eql(3)
    # will fetch a system group with a range
    header 'Range', 'items=2-3'
    get 'api/system_groups'
    expect(last_response.status).to eql(206)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
  end
  it 'will update a system group with put' do
    get 'api/system_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    put 'api/system_groups/' + id_1, { id: '100', name: 'sysGroupModified1', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(200)
    # will return 400 as body is not passed
    put 'api/system_groups/' + id_1
    expect(last_response.status).to eql(400)
  end
  it 'will show a system group with a given id' do
    get 'api/system_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    get 'api/system_groups/' + id_1
    expect(last_response.status).to eql(200)
    # passing an incorrect id
    id_1 = 'incorrect123'
    get 'api/system_groups/' + id_1
    expect(last_response.status).to eql(404)
  end

  it 'will delete a system group with a given id' do
    get 'api/system_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    delete 'api/system_groups/' + id_1
    expect(last_response.status).to eql(204)
    # passing a wrong system groupid
    id_1 = 'incorrect1234'
    delete 'api/system_groups/' + id_1
    expect(last_response.status).to eql(404)
  end

  it 'will apply policy_group(s) to a system_group post api' do
    # using get method of system group to get a valid system_group id
    get 'api/system_groups'
    body = JSON.parse(last_response.body)
    require 'pp'
    id_1 = JSON.parse((body[1]).to_json)['id']
    # using get method of policy group to get a valid policy_group id
    get 'api/policy_groups'
    p_body = JSON.parse(last_response.body)
    id_2 = JSON.parse((p_body[0]).to_json)['id']
    # passing valid system_group id and policy_group id array
    post 'api/system_groups/' + id_1, [id_2].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(204)
    # passing invalid system_group id and valid policy_group id array
    post 'api/system_groups/' + 'we345678', [id_2].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(404)
    # passing empty array in body
    post 'api/system_groups/' + id_1 , [].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(400)
    # passing empty  body
    post 'api/system_groups/' + id_1
    expect(last_response.status).to eql(400)
  end

  it 'will add a system(s) to a system group' do
    # get system group id
    get 'api/system_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[0]).to_json)['id']
    # getting 2 valid system ids
    get 'api/systems'
    body_sys = JSON.parse(last_response.body)
    system_id = JSON.parse((body_sys[0]).to_json)['id']
    system_id1 = JSON.parse((body_sys[1]).to_json)['id']
    # passing correct params
    post 'api/system_groups/' + id_1 + '/members', [system_id, system_id1].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(204)
    # passing invalid systemGroup id
    id_2 = '0oi8u7'
    post 'api/system_groups/' + id_1 + '/members', [id_2].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(400)
    # passing invalid system group id
    get 'api/system_groups/12345tygh/members'
    expect(last_response.status).to eql(404)
  end

  it 'will list the system group members' do
    get 'api/system_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[0]).to_json)['id']
    # passing correct parameters
    get 'api/system_groups/' + id_1 + '/members'
    expect(last_response.status).to eql(200)
    # passing invalid system group id
    get 'api/system_groups/12345tygh/members'
    expect(last_response.status).to eql(404)
  end

  it 'will remove a system from a system group' do
    # get system group id
    get 'api/system_groups'
    body = JSON.parse(last_response.body)
    # this id has systems as we have added a system in the above block
    id_1 = JSON.parse((body[0]).to_json)['id']
    # passing correct params
    get 'api/system_groups/' + id_1 + '/members'
    require 'pp'
    system_body = JSON.parse(last_response.body)
    system_id = JSON.parse((system_body[0]).to_json)['id']
    # passing all valid parameters for DELETE api
    delete 'api/system_groups/' + id_1 + '/members/' + system_id
    expect(last_response.status).to eql(204)
    # passing incorrect system group id
    delete 'api/system_groups/IamIncorrectId/members/' + system_id
    expect(last_response.status).to eql(404)
    # passing incorrect system id
    delete 'api/system_groups/' + id_1 + '/members/InCorrectSystemId'
    expect(last_response.status).to eql(400)
  end
  it 'will show compliance level of a system group' do
    # get system group id
    get 'api/system_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    # this id has systems as we have added a system in the above block
    id_1 = JSON.parse((body[0]).to_json)['id']
    get 'api/system_groups/' + id_1 + '/compliance'
    expect(last_response.status).to eql(200)
    # passing incorrect system group id
    id_1 = '12345'
    get 'api/system_groups/' + id_1 + '/compliance'
    expect(last_response.status).to eql(404)
  end
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
  # Tests for policy_groups APIs

  # 1. Tests for POST API i.e. post /api/policy_groups

  it 'will create a new policy group given a name' do
    post '/api/policy_groups', { name: 'mytestgroup' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup')

    post '/api/policy_groups', { name: 'mytestgroup1' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup1')

    post '/api/policy_groups', { name: 'mytestgroup2' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup2')

    post '/api/policy_groups'
    expect(last_response.status).to eql(400)

  end

  # 2. Tests for GET API i.e. get /api/policy_groups

  it 'will list the policy groups' do
    get '/api/policy_groups'
    expect(last_response.status).to eql(200)
  end

  it 'will return a policy group with a range' do
    header 'Range', 'items=1-2'
    get '/api/policy_groups'
    expect(last_response.status).to eql(206)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
  end

  # 3. Tests for PUT API i.e. put /api/policy_groups/{id}

  it 'will update a policy group with provided id' do
    get '/api/policy_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']

    policy_group = Sentinel::Models::PolicyGroup.new(name: 'policy group1')
    policy_group.save

    put '/api/policy_groups/' + id_1, { name: 'Updated_Policy_Name' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)['name']).to eql('Updated_Policy_Name')

    put '/api/policy_groups/' + id_1, { name: 'Updated_Policy_Name' }.to_json
    expect(last_response.status).to eql(400)

    put '/api/policy_groups/xyz', { name: 'Updated_Policy_Name' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(404)

  end

  # 4. Tests for GET API i.e. get /api/policy_groups/{id}

  it 'will return a policy group with provided id' do
    get '/api/policy_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    policy_name_1 = JSON.parse((body[1]).to_json)['name']

    get '/api/policy_groups/' + id_1
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)['name']).to eql(policy_name_1)

    get '/api/policy_groups/xyz'
    expect(last_response.status).to eql(404)

  end

  # 5. Tests for DELETE API i.e. delete /api/policy_groups/{id}

  it 'will delete a policy group with provided id' do
    get '/api/policy_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']
    size = body.size

    delete '/api/policy_groups/xyz'
    expect(last_response.status).to eql(404)
    get '/api/policy_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to eql(size)

    delete '/api/policy_groups/' + id_1
    expect(last_response.status).to eql(204)
    get '/api/policy_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to eql(size - 1)

  end

  # 6. Tests for GET API i.e. get /api/policy_groups/{id}/members
  it 'will list the policy group members of given id' do
    get '/api/policy_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[1]).to_json)['id']

    get '/api/policy_groups/' + id_1 + '/members'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)

    get '/api/policy_groups/xyz/members'
    expect(last_response.status).to eql(404)

  end

  # 7. Tests for POST API i.e. post/policy_group/{id}/members
  it 'will add policies to the policy group with given id' do
    get '/api/policy_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[0]).to_json)['id']

    policy_1 = Sentinel::Models::Policy.new(name: 'Policy_test1')
    policy_1.save
    id_4 = policy_1.id
    policy_2 = Sentinel::Models::Policy.new(name: 'Policy_test2')
    policy_2.save
    policy_3 = Sentinel::Models::Policy.new(name: 'Policy_test3')
    policy_3.save

    post '/api/policy_groups/' + id_1 + '/members', [id_4].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(204)

    # bad request with invalid policy_id array
    post '/api/policy_groups/' + id_1 + '/members', ['id5'].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(400)

    post '/api/policy_groups/xyz/members' , [id_4].to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(404)

  end

  # 8. Tests for DELETE API i.e. delete /api/policy_groups/{id}/members/{policy_id}
  it 'will delete policy with policy id from policy group' do

    get '/api/policy_groups'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    id_1 = JSON.parse((body[0]).to_json)['id']

    get '/api/policy_groups/' + id_1 + '/members'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    policy_id = JSON.parse((body[0]).to_json)['id']

    delete '/api/policy_groups/' + id_1 + '/members/' + policy_id
    expect(last_response.status).to eql(204)

    delete '/api/policy_groups/' + id_1 + '/members/xyz'
    expect(last_response.status).to eql(400)

    delete '/api/policy_groups/xyz/members/abc'
    expect(last_response.status).to eql(404)

  end

  # Tests for policies APIS
  # 1. Test for GET API i.e. get /api/policies
  it 'will give the list of policies' do

    get '/api/policies'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(last_response.status).to eql(200)

  end

  it 'will return a policies given a range' do

    header 'Range', 'items=1-2'
    get '/api/policies'
    expect(last_response.status).to eql(206)

  end

  # 2. Test for PUT API i.e. put /api/policies/{id}
  it 'will update the policy given an id' do

    get '/api/policies'
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    policy_id = JSON.parse((body[0]).to_json)['id']

    put '/api/policies/' + policy_id, { grace_period: 30 }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)['grace_period']).to eql(30)

    put '/api/policies/' + policy_id, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(400)

    put '/api/policies/xyz', { description: 'policy_updated' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eql(404)
  end
  # 3. Test for GET API i.e. /api/policies/{id}
  it 'will return polict given an id' do
    policy_5 = Sentinel::Models::Policy.new(name: 'Policy_test5')
    policy_5.save

    get '/api/policies/' + policy_5.id
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)['name']).to eql('Policy_test5')

    get '/api/policies/xyz'
    expect(last_response.status).to eql(404)
  end
  # 4. Test for GET API i.e. /api/policies/{id}/parameters
  it 'will return polict given an id' do
    policy_6 = Sentinel::Models::Policy.new(name: 'Policy_test6', description: 'This is test policy')
    policy_6.save

    get '/api/policies/' + policy_6.id + '/parameters'
    expect(last_response.status).to eql(200)

    get '/api/policies/xyz/parameters'
    expect(last_response.status).to eql(404)

  end
  after :all do
    Sentinel::Store.indices.delete index: 'testing'
  end
end
