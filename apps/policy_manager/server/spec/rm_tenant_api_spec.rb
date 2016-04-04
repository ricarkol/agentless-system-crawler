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


    @tenants = {}
    @users = {}

    SentinelDocker::Models.constants.each do |model|
      next if model == :Base
      model = SentinelDocker::Models.const_get(model)
      model.do_mapping
    end

    begin
      tenant = SentinelDocker::Models::Tenant.new(name: 'IBM', owner_namespaces: %w[ibm_ns])
      fail tenant.errors.full_messages.join(',') unless tenant.save
      @tenants[tenant.id] = tenant.name
    rescue
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

  it 'will create a tenant' do

    (0...5).each do |i|
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
      @tenants[body['id']] = body['name']
    end    

    post 'api/tenants', { name: 'tenant1' }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(400)

    post 'api/tenants', { name: '' }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(400)

  end

  it 'will show a tenant with a given id' do

    @tenants.each do |k,v|
      get 'api/tenants'+"/#{k}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['name']).to eql(v)
    end

    get 'api/tenants'+"/dummy_id", {}, 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.ok?).to be(false)
    expect(last_response.status).to eql(404)

  end

  it 'will list tenants' do
    get 'api/tenants', {}, 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.ok?).to be(true)
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.size).to eql(@tenants.size)
    body.each do |t|
      expect(@tenants.has_key? t['id']).to be(true)
    end 
  end

  it 'will list tenants according to a "Range: items=n-m" header' do
    get 'api/tenants', {}, 'rack.session' => {'identity' => 'ibm_admin'}
    content_range = last_response.headers['Content-Range']
    expect(content_range).to be_a(String)
    expect(content_range).to eq("items 1-#{@tenants.size}/#{@tenants.size}")
    header 'Range', "items=2-#{@tenants.size-1}"
    get 'api/tenants', {}, 'rack.session' => {'identity' => 'ibm_admin'}
    content_range = last_response.headers['Content-Range']
    expect(content_range).to eq("items 2-#{@tenants.size-1}/#{@tenants.size}")
  end

  it 'will update a tenant with put' do
    @tenants.each do |id, name|
      get 'api/tenants'+"/#{id}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      owner_namespaces = JSON.parse(last_response.body)['owner_namespaces'] || []
      expect(owner_namespaces).to be_a(Array)
      new_owner_ns = "ns_#{name}_1"
      owner_namespaces << new_owner_ns
      put 'api/tenants/' + id, { owner_namespaces: owner_namespaces }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.status).to eql(200)
      get 'api/tenants'+"/#{id}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['owner_namespaces']).to be_a(Array)
      expect(JSON.parse(last_response.body)['owner_namespaces'].include? new_owner_ns).to be(true)
    end

    put 'api/tenants/dummy_id', { owner_namespaces: ['aaa', 'bbb']}.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(404)
  
    put 'api/tenants', { owner_namespaces: ['aaa', 'bbb']}.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(405)

    put 'api/tenants'+"/#{@tenants.keys[0]}", 'xxxxxxyyyyy', 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(400)
  
  end

  it 'will delete a tenant with a given id' do
    tenant_ids = @tenants.keys
    tenant_ids.each do |id|
      next if @tenants[id] == 'IBM'
      delete 'api/tenants/' + id, {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.status).to eql(204)
      @tenants.delete(id)
    end


    delete 'api/tenants/dummy_id', {}, 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(404)
  
    delete 'api/tenants', {}, 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(405)
  end

  it 'will allow only show its own tenant by a user' do

    users = {}
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
      @tenants[tenant_id] = body['name']

      post 'api/users', {identity: "admin_#{i}", tenant_id: tenant_id}.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'} 
      expect(last_response.status).to eql(201) 
      body = JSON.parse(last_response.body)
      expect(body['id']).not_to be_nil
      expect(body['identity']).to eq("admin_#{i}")
      expect(body['tenant_id']).to eql(tenant_id)
      users[tenant_id] = body
    end    

    @tenants.each do |id, name|
      get 'api/tenants'+"/#{id}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['name']).to eql(name)
    end

    # allow to get user's own tenant
    users.each do |tenant_id, user|
      @tenants.each do |id, name|
        get 'api/tenants'+"/#{id}", {}, 'rack.session' => {'identity' => user['identity']}
        if id == tenant_id
          expect(last_response.ok?).to be(true)
          expect(last_response.status).to eql(200)
          expect(JSON.parse(last_response.body)['name']).to eql(name)
        else
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(403)
        end
      end
    end

    # block post, put, delete, get lists
    users.each do |tenant_id, user|
      @tenants.each do |id, name|
        get 'api/tenants', {}, 'rack.session' => {'identity' => user['identity']}
        expect(last_response.ok?).to be(false)
        expect(last_response.status).to eql(403)

        put 'api/tenants/' + id, { owner_namespaces: %w[aaa bbb] }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => user['identity']}
        expect(last_response.ok?).to be(false)
        expect(last_response.status).to eql(403)

        delete 'api/tenants/' + id, {}, 'rack.session' => {'identity' => user['identity']}
        expect(last_response.ok?).to be(false)
        expect(last_response.status).to eql(403)

      end

      post 'api/tenants', {name: "tenant_c", owner_namespaces: %w[tc_ns1 tc_ns2]}.to_json, 'rack.session' => {'identity' => user['identity']}
      expect(last_response.ok?).to be(false)
      expect(last_response.status).to eql(403)
    end

    @tenants.each do |id, name|
      next if name == 'IBM'
      delete 'api/tenants/' + id, {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.status).to eql(204)

      get 'api/tenants'+"/#{id}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(false)
      expect(last_response.status).to eql(404)

      get 'api/users'+"/#{users[id]['id']}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(false)
      expect(last_response.status).to eql(404)

      @tenants.delete(id)
    end

  end

  after :all do
    SentinelDocker::Store.indices.delete index: 'api_testing'
  end
end
