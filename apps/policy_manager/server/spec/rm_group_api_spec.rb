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

    @test_data = {}

    SentinelDocker::Models.constants.each do |model|
      next if model == :Base
      model = SentinelDocker::Models.const_get(model)
      model.do_mapping
    end

    begin
      tenant = SentinelDocker::Models::Tenant.new(name: 'IBM', owner_namespaces: %w[ibm_ns])
      fail tenant.errors.full_messages.join(',') unless tenant.save
    rescue => e
      puts 'tenant <IBM> not created. Already existed.'
    end

    begin
      user = SentinelDocker::Models::User.new(identity: 'ibm_admin')
      user.tenant_id = tenant.id
      fail user.errors.full_messages.join(',') unless user.save
    rescue
      puts 'user <ibm_admin> not created. Already existed.'
    end

    begin
      group = SentinelDocker::Models::Group.new(name: 'UNKNOWN')
      group.tenant_id = tenant.id
      group.default = true
      fail group.errors.full_messages.join(',') unless group.save
    rescue
      puts 'user <ibm_admin> not created. Already existed.'
    end

  end

  it 'will create a group' do

    conf = {
      name: "tenant_a",
      owner_namespaces: [
        "ta_ns1",
        "ta_ns2"
      ]
    }
    post 'api/tenants', conf.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(201)
    body = JSON.parse(last_response.body)
    expect(body['id']).not_to be_nil
    expect(body['name']).to eql(conf[:name])
    tenant_id = body['id']
    @test_data[:tenant] = body

    post 'api/users', {identity: "admin_a", tenant_id: tenant_id}.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(201)
    body = JSON.parse(last_response.body)
    expect(body['id']).not_to be_nil
    expect(body['identity']).to eq("admin_a")
    expect(body['tenant_id']).to eql(tenant_id)
    @test_data[:user] = body

    groups = {}
    (0...5).each do |i|
      conf = {
        name: "group#{i}",
        tenant_id: @test_data[:tenant]['id'],
        default: true
      }
      if i==0
        post 'api/groups'+"?tenant=#{@test_data[:tenant]['name']}", conf.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
      else
        post 'api/groups', conf.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => @test_data[:user]['identity']}
      end

      expect(last_response.status).to eql(201)
      body = JSON.parse(last_response.body)
      expect(body['id']).not_to be_nil
      expect(body['name']).to eql(conf[:name])
      groups[body['id']] = body
    end
    @test_data[:groups] = groups

    post 'api/groups', { name: @test_data[:groups].values[0]['name'] }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => @test_data[:user]['identity']}
    expect(last_response.status).to eql(400)

    post 'api/groups', { name: '' }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => @test_data[:user]['identity']}
    expect(last_response.status).to eql(400)

  end

  it 'will show a group with a given id' do

    @test_data[:groups].each do |id, group|
      get 'api/groups'+"/#{id}"+"?tenant=#{@test_data[:tenant]['name']}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['name']).to eql(group['name'])

      get 'api/groups'+"/#{id}", {}, 'rack.session' => {'identity' => @test_data[:user]['identity']}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['name']).to eql(group['name'])

    end

    get 'api/groups'+"/dummy_id", {}, 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.ok?).to be(false)
    expect(last_response.status).to eql(404)

  end

  it 'will list groups' do

    # access groups in an tenant by ibm_admin
    get 'api/groups'+"?tenant=#{@test_data[:tenant]['name']}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.ok?).to be(true)
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to eql(@test_data[:groups].size)
    body.each do |g|
      expect(@test_data[:groups].has_key? g['id']).to be(true)
    end

    # access groups in IBM tenant by ibm_admin
    get 'api/groups', {}, 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.ok?).to be(true)
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to eql(1)
    expect(body[0]['name']).to eq('UNKNOWN')

    # access groups in an tenant by a tenant admin
    get 'api/groups', {}, 'rack.session' => {'identity' => @test_data[:user]['identity']}
    expect(last_response.ok?).to be(true)
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to eql(@test_data[:groups].size)
    body.each do |g|
      expect(@test_data[:groups].has_key? g['id']).to be(true)
    end

  end

  it 'will list groups according to a "Range: items=n-m" header' do
    groups = @test_data[:groups]
    get 'api/groups', {}, 'rack.session' => {'identity' => @test_data[:user]['identity']}
    content_range = last_response.headers['Content-Range']
    expect(content_range).to be_a(String)
    expect(content_range).to eq("items 1-#{groups.size}/#{groups.size}")
    header 'Range', "items=2-#{groups.size-1}"
    get 'api/groups', {}, 'rack.session' => {'identity' => @test_data[:user]['identity']}
    content_range = last_response.headers['Content-Range']
    expect(content_range).to eq("items 2-#{groups.size-1}/#{groups.size}")
  end

  it 'will update a group with put' do
    groups = @test_data[:groups]
    groups.each do |id, name|
      put 'api/groups'+"/#{id}", {default: false}.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => @test_data[:user]['identity']}
      expect(last_response.status).to eql(200)
      get 'api/groups'+"/#{id}", {}, 'rack.session' => {'identity' => @test_data[:user]['identity']}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['default']).to be(false)
    end

    put 'api/groups/dummy_id', {default: false}.to_json , 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => @test_data[:user]['identity']}
    expect(last_response.status).to eql(404)

    put 'api/groups', {default: false}.to_json , 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => @test_data[:user]['identity']}
    expect(last_response.status).to eql(405)

    put 'api/groups'+"/#{groups.keys[0]}", 'xxxxxxyyyyy', 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => @test_data[:user]['identity']}
    expect(last_response.status).to eql(400)

  end

  it 'will delete a group with a given id' do
    groups = @test_data[:groups]
    group_ids = groups.keys
    group_ids.each do |id|
      delete 'api/groups/' + id, {}, 'rack.session' => {'identity' => @test_data[:user]['identity']}
      expect(last_response.status).to eql(204)
      groups.delete(id)
    end
    @test_data[:groups] = groups

    delete 'api/groups/dummy_id', {}, 'rack.session' => {'identity' => @test_data[:user]['identity']}
    expect(last_response.status).to eql(404)

    delete 'api/groups', {}, 'rack.session' => {'identity' => @test_data[:user]['identity']}
    expect(last_response.status).to eql(405)

    delete 'api/tenants/' + @test_data[:tenant]['id'], {}, 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(204)

  end

  it 'will allow only show its own group by a user' do

    #ibm_admin : UNKNOWN@ibm or groups for any tenant
    #admin_x : groups for the tenant


    users = {}
    test_data_array = []
    (0...2).each do |i|
      conf = {
        name: "tenant#{i}",
        owner_namespaces: [
          "t#{i}_ns1",
          "t#{i}_ns2"
        ]
      }
      post 'api/tenants', conf.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.status).to eql(201)
      body = JSON.parse(last_response.body)
      expect(body['id']).not_to be_nil
      expect(body['name']).to eql(conf[:name])
      tenant_id = body['id']
      test_data = { tenant: body }


      post 'api/users', {identity: "admin_#{i}", tenant_id: tenant_id}.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.status).to eql(201)
      body = JSON.parse(last_response.body)
      expect(body['id']).not_to be_nil
      expect(body['identity']).to eq("admin_#{i}")
      expect(body['tenant_id']).to eql(tenant_id)
      test_data[:user] = body

      conf = {
        name: "group#{i}",
        tenant_id: tenant_id,
        default: true
      }
      post 'api/groups', conf.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => test_data[:user]['identity']}
      expect(last_response.status).to eql(201)
      body = JSON.parse(last_response.body)
      expect(body['id']).not_to be_nil
      expect(body['name']).to eql(conf[:name])
      group_id = body['id']
      test_data[:group] = body

      test_data_array << test_data

    end

    test_data_array.each do |test_data|
      id = test_data[:group]['id']
      name = test_data[:group]['name']
      tenant_name = test_data[:tenant]['name']
      get 'api/groups'+"/#{id}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(false)
      expect(last_response.status).to eql(404)

      get 'api/groups'+"/#{id}"+"?tenant=#{tenant_name}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['name']).to eql(name)
    end

    # allow to get user's own group
    test_data_array.each do |test_data_1|
      user = test_data_1[:user]
      tenant1 = test_data_1[:tenant]
      group1 = test_data_1[:group]
      test_data_array.each do |test_data_2|
        group2 = test_data_2[:group]
        tenant2 = test_data_2[:tenant]
        if tenant1['id'] == tenant2['id']
          get 'api/groups'+"/#{group2['id']}", {}, 'rack.session' => {'identity' => user['identity']}
          expect(last_response.ok?).to be(true)
          expect(last_response.status).to eql(200)
          expect(JSON.parse(last_response.body)['name']).to eql(group2['name'])

          get 'api/groups', {}, 'rack.session' => {'identity' => user['identity']}
          expect(last_response.ok?).to be(true)
          expect(last_response.status).to eql(200)
          body = JSON.parse(last_response.body)
          expect(body).to be_a(Array)
          expect(body.size).to eql(1)

          put 'api/groups/' + group2['id'], { owner_namespaces: %w[aaa bbb] }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => user['identity']}
          expect(last_response.ok?).to be(true)
          expect(last_response.status).to eql(200)

        else
          get 'api/groups'+"/#{group2['id']}", {}, 'rack.session' => {'identity' => user['identity']}
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

          get 'api/groups'+"/#{group2['id']}"+"?tenant=#{tenant2['name']}", {}, 'rack.session' => {'identity' => user['identity']}
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

          get 'api/groups'+"?tenant=#{tenant2['name']}", {}, 'rack.session' => {'identity' => user['identity']}
          expect(last_response.ok?).to be(true)
          expect(last_response.status).to eql(200)
          body = JSON.parse(last_response.body)
          expect(body).to be_a(Array)
          expect(body.size).to eql(1)
          expect(body.select {|g| g['id']==group1['id']}.empty?).to be(false)

          put 'api/groups/' + group2['id'], { owner_namespaces: %w[aaa bbb] }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => user['identity']}
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

          put 'api/groups/' + group2['id'] + "?tenant=#{tenant2['name']}", { owner_namespaces: %w[aaa bbb] }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => user['identity']}
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

          delete 'api/groups/' + group2['id'], {}, 'rack.session' => {'identity' => user['identity']}
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

          delete 'api/groups/' + group2['id'] + "?tenant=#{tenant2['name']}", {}, 'rack.session' => {'identity' => user['identity']}
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

        end

      end
    end

    test_data_array.each do |test_data_1|
      user = test_data_1[:user]
      tenant = test_data_1[:tenant]
      group = test_data_1[:group]

      conf = {
        name: "group_d",
        tenant_id: tenant['id'],
        default: false
      }
      post 'api/groups', conf.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => user['identity']}
      expect(last_response.status).to eql(201)
      body = JSON.parse(last_response.body)
      expect(body['id']).not_to be_nil
      expect(body['name']).to eql(conf[:name])
      new_group_id = body['id']

      delete 'api/groups/' + group['id'], {}, 'rack.session' => {'identity' => user['identity']}
      expect(last_response.ok?).to be(false)
      expect(last_response.status).to eql(500)

      get 'api/groups/'+new_group_id, {}, 'rack.session' => {'identity' => user['identity']}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      body = JSON.parse(last_response.body)
      expect(body['default']).to be(false)

      delete 'api/groups/' + new_group_id, {}, 'rack.session' => {'identity' => user['identity']}
      expect(last_response.status).to eql(204)

      get 'api/groups/'+new_group_id, {}, 'rack.session' => {'identity' => user['identity']}
      expect(last_response.ok?).to be(false)
      expect(last_response.status).to eql(404)
    end

  end

  #delete image
  #delete rule



  after :all do
    SentinelDocker::Store.indices.delete index: 'api_testing'
  end
end
