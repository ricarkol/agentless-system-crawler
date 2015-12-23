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

  #default setup
  #user: ibm_admin
  #tenant: IBM
  #group: UNKNOWN
  #rules:

  # 1. Tenants
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


  # 2. Groups

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
      post 'api/groups', conf.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.status).to eql(201)
      body = JSON.parse(last_response.body)
      expect(body['id']).not_to be_nil
      expect(body['name']).to eql(conf[:name])
      groups[body['id']] = body
    end
    @test_data[:groups] = groups

    post 'api/groups', { name: @test_data[:groups].values[0]['name'] }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(400)

    post 'api/groups', { name: '' }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.status).to eql(400)

  end

  it 'will show a group with a given id' do

    @test_data[:groups].each do |id, name|
      get 'api/groups'+"/#{id}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['name']).to eql(name)
    end

    get 'api/groups'+"/dummy_id", {}, 'rack.session' => {'identity' => 'ibm_admin'}
    expect(last_response.ok?).to be(false)
    expect(last_response.status).to eql(404)

  end

  it 'will list groups' do
      get 'api/groups', { tenant: @test_data[:tenant]['name'] }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      body = JSON.parse(last_response.body)
      expect(body).to be_a(Array)
      expect(body.size).to eql(@test_data[:groups].size)
      body.each do |g|
        expect(@test_data[:groups].has_key? g['id']).to be(true)
      end

      get 'api/groups', {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      body = JSON.parse(last_response.body)
      expect(body).to be_a(Array)
      expect(body.size).to eql(1)
      expect(body[0]['name']).to be('UNKNOWN')

      get 'api/groups', {}, 'rack.session' => {'identity' => @test_data[:user]['name']}
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
      get 'api/groups', {}, 'rack.session' => {'identity' => 'ibm_admin'}
      content_range = last_response.headers['Content-Range']
      expect(content_range).to be_a(String)
      expect(content_range).to eq("items 1-#{groups.size}/#{groups.size}")
      header 'Range', "items=2-#{groups.size-1}"
      get 'api/groups', {}, 'rack.session' => {'identity' => 'ibm_admin'}
      content_range = last_response.headers['Content-Range']
      expect(content_range).to eq("items 2-#{groups.size-1}/#{groups.size}")
    end

    it 'will update a group with put' do
      groups = @test_data[:groups]
      groups.each do |id, name|
        put 'api/groups'+"/#{id}", {default: false}.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
        expect(last_response.status).to eql(200)
        get 'api/groups'+"/#{id}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
        expect(last_response.ok?).to be(true)
        expect(last_response.status).to eql(200)
        expect(JSON.parse(last_response.body)['default']).to be_false
      end

      put 'api/groups/dummy_id', {default: false}.to_json , 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.status).to eql(404)

      put 'api/groups', {default: false}.to_json , 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.status).to eql(405)

      put 'api/groups'+"/#{groups.keys[0]}", 'xxxxxxyyyyy', 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.status).to eql(400)

    end

    it 'will delete a group with a given id' do
      groups = @test_data[:groups]
      group_ids = groups.keys
      group_ids.each do |id|
        delete 'api/groups/' + id, {}, 'rack.session' => {'identity' => 'ibm_admin'}
        expect(last_response.status).to eql(204)
        groups.delete(id)
      end
      @test_data[:groups] = groups

      delete 'api/groups/dummy_id', {}, 'rack.session' => {'identity' => 'ibm_admin'}
      expect(last_response.status).to eql(404)

      delete 'api/groups', {}, 'rack.session' => {'identity' => 'ibm_admin'}
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
          name: "group#{i}",
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
        test_data[:tenant] = body


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
        post 'api/groups', conf.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => 'ibm_admin'}
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
        get 'api/groups'+"/#{id}", {}, 'rack.session' => {'identity' => 'ibm_admin'}
        expect(last_response.ok?).to be(true)
        expect(last_response.status).to eql(200)
        expect(JSON.parse(last_response.body)['name']).to eql(name)
      end

      # allow to get user's own group
      test_data_array.each do |test_data_1|
        user = test_data_1[:user]
        tenant_u = test_data_1[:tenant]
        group_u = test_data_1[:group]
        test_data_array.each do |test_data_2|
          group = test_data_2[:group]
          tenant_g = test_data_1[:tenant]
          if tenant_u.id == tenant_g.id
            get 'api/groups'+"/#{group['id']}", {}, 'rack.session' => {'identity' => user['identity']}
            expect(last_response.ok?).to be(true)
            expect(last_response.status).to eql(200)
            expect(JSON.parse(last_response.body)['name']).to eql(name)

            get 'api/groups', {}, 'rack.session' => {'identity' => user['identity']}
            expect(last_response.ok?).to be(true)
            expect(last_response.status).to eql(200)
            body = JSON.parse(last_response.body)
            expect(body).to be_a(Array)
            expect(body.size).to eql(group_u.size)

            put 'api/groups/' + group['id'], { owner_namespaces: %w[aaa bbb] }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => user['identity']}
            expect(last_response.ok?).to be(true)
            expect(last_response.status).to eql(200)

            delete 'api/groups/' + group['id'], {}, 'rack.session' => {'identity' => user['identity']}
            expect(last_response.ok?).to be(true)
            expect(last_response.status).to eql(200)

            get 'api/groups/'+group['id'], {}, 'rack.session' => {'identity' => user['identity']}
            expect(last_response.ok?).to be(false)
            expect(last_response.status).to eql(404)

          else
            get 'api/groups'+"/#{group['id']}", {}, 'rack.session' => {'identity' => user['identity']}
            expect(last_response.ok?).to be(false)
            expect(last_response.status).to eql(403)

            get 'api/groups', {}, 'rack.session' => {'identity' => user['identity']}
            expect(last_response.ok?).to be(false)
            expect(last_response.status).to eql(403)

            put 'api/groups/' + group['id'], { owner_namespaces: %w[aaa bbb] }.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => user['identity']}
            expect(last_response.ok?).to be(false)
            expect(last_response.status).to eql(403)

            delete 'api/groups/' + group['id'], {}, 'rack.session' => {'identity' => user['identity']}
            expect(last_response.ok?).to be(false)
            expect(last_response.status).to eql(403)

          end

        end
      end

    end

    #delete image
    #delete rule



    ##################
    it 'will create a group' do

    end

    it 'will show a group with a given id' do

    end

    it 'will list groups' do

    end

    it 'will list groups according to a "Range: items=n-m" header' do

    end

    it 'will update a group with put' do

    end

    it 'will delete a group with a given id' do

    end

    # 3. Rules
    it 'will create a rule' do

    end

    it 'will show a rule with a given id' do

    end

    it 'will list rules' do

    end

    it 'will list rules according to a "Range: items=n-m" header' do

    end

    it 'will update a rule with put' do

    end

    it 'will delete a rule with a given id' do

    end

    it 'will return a rule zip file with a given id' do

    end

    it 'will show a parameter with a given id' do

    end

    it 'will delete rules with given array of ids' do

    end

    # 4. Users
    it 'will create a user' do

    end

    it 'will show a user with a given id' do

    end

    it 'will list users' do

    end

    it 'will list users according to a "Range: items=n-m" header' do

    end

    it 'will update a user with put' do

    end

    it 'will delete a user with a given id' do

    end


    # 5. Images
    it 'will show a image with a given id' do

    end

    it 'will list images' do

    end

    it 'will list images according to a "Range: items=n-m" header' do

    end

    it 'will update a image with put' do

    end

    it 'will delete a image with a given id' do

    end

    it 'will show a compliance status with a given id' do

    end

    # 6. Services

    # do_nothing
    it 'do_nothing' do

    end

    # get_rules
    it 'get_rules' do

    end

    # get_rules_per_tenant
    it 'get_rules_per_tenant' do

    end

    # get_image_status_per_tenant
    it 'get_image_status_per_tenant' do

    end
    # get_groups
    it 'get_groups' do

    end

    # get_tenant_rules
    it 'get_tenant_rules' do

    end

    # set_namespaces_to_group
    it 'set_namespaces_to_group' do

    end

    # set_tenant_rules
    it 'set_tenant_rules' do

    end

    # get_auto_assign
    it 'get_auto_assign' do

    end

    # set_auto_assign
    it 'set_auto_assign' do

    end

    # get_snapshot_page
    it 'get_snapshot_page' do

    end

    # get_result
    it 'get_result' do

    end

    # get_namespaces
    it 'get_namespaces' do

    end

    # get_crawl_times
    it 'get_crawl_times' do

    end

    # get_result_page_per_namespace
    it 'get_result_page_per_namespace' do

    end

    # get_vulnerability_page
    it 'get_vulnerability_page' do

    end

    # get_vulnerability_counts
    it 'get_vulnerability_counts' do

    end

    # get_rule_descriptions
    it 'get_rule_descriptions' do

    end



    # it 'will return a JSON array on resource collections' do
    #   get 'api/rules'
    #   expect(last_response.ok?).to be(true)

    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    # end

    # it 'will return items according to a "Range: items=n-m" header' do
    #   (0...10).each do |i|
    #     c = Container.new(container_id: "container#{i}", container_name: "container#{i}", image_id: "image#{i}", created: "1000#{i}")
    #     expect(c.save).to be(true)
    #   end

    #   get 'api/containers'
    #   expect(last_response.ok?).to be(true)

    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   expect(body.size).to be(10)

    #   content_range = last_response.headers['Content-Range']
    #   expect(content_range).to be_a(String)
    #   expect(content_range).to eq('items 1-10/10')

    #   header 'Range', 'items=5-9'
    #   get 'api/containers'
    #   expect(last_response.status).to be(206)
    #   body = JSON.parse(last_response.body)
    #   expect(body.size).to be(5)
    # end

    # it 'will return a "Content-Range: items n-m/total" header' do
    #   get 'api/containers'
    #   content_range = last_response.headers['Content-Range']
    #   expect(content_range).to be_a(String)
    #   expect(content_range).to eq('items 1-10/10')

    #   header 'Range', 'items=5-9'
    #   get 'api/containers'
    #   content_range = last_response.headers['Content-Range']
    #   expect(content_range).to eq('items 5-9/10')
    # end

    # # testing blocks for container groups
    # it 'will create a rule group given a name' do
    #   post 'api/rule_groups', { name: 'mytestgroup1' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(201)
    #   expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup1')
    #   # passing name and description
    #   post 'api/container_groups', { name: 'containerGroup2', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(201)
    #   expect(JSON.parse(last_response.body)['name']).to eql('containerGroup2')
    #   expect(JSON.parse(last_response.body)['description']).to eql('Hello putting some description')
    #   post 'api/container_groups', { name: 'containerGroup3', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(201)
    #   expect(JSON.parse(last_response.body)['name']).to eql('containerGroup3')
    #   # will create a container group given a name ,description and id
    #   post 'api/container_groups', { id: '100', name: 'containerGroup4', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(201)
    #   expect(JSON.parse(last_response.body)['name']).to eql('containerGroup4')
    #   # will not create a container rule as name is not sent
    #   post 'api/container_groups', { id: '100', name: ' ', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(400)
    # end

    # it 'will list the container groups' do
    #   get 'api/container_groups'
    #   expect(last_response.status).to eql(200)
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   expect(body.size).to eql(3)
    #   # will fetch a container group with a range
    #   header 'Range', 'items=2-3'
    #   get 'api/container_groups'
    #   expect(last_response.status).to eql(206)
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    # end

    # it 'will update a container group with put' do
    #   get 'api/container_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   id_1 = JSON.parse((body[1]).to_json)['id']
    #   put 'api/container_groups/' + id_1, { id: '100', name: 'containerGroupModified1', description: 'Hello putting some description' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(200)
    #   # will return 400 as body is not passed
    #   put 'api/container_groups/' + id_1
    #   expect(last_response.status).to eql(400)
    # end

    # it 'will show a container group with a given id' do
    #   get 'api/container_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   id_1 = JSON.parse((body[1]).to_json)['id']
    #   get 'api/container_groups/' + id_1
    #   expect(last_response.status).to eql(200)
    #   # passing an incorrect id
    #   id_1 = 'incorrect123'
    #   get 'api/container_groups/' + id_1
    #   expect(last_response.status).to eql(404)
    # end

    # it 'will delete a container group with a given id' do
    #   get 'api/container_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   id_1 = JSON.parse((body[1]).to_json)['id']
    #   delete 'api/container_groups/' + id_1
    #   expect(last_response.status).to eql(204)
    #   # passing a wrong container groupid
    #   id_1 = 'incorrect1234'
    #   delete 'api/container_groups/' + id_1
    #   expect(last_response.status).to eql(404)
    # end

    # it 'will apply rule_group(s) to a container_group post api' do
    #   # using get method of container group to get a valid container_group id
    #   get 'api/container_groups'
    #   body = JSON.parse(last_response.body)
    #   require 'pp'
    #   id_1 = JSON.parse((body[1]).to_json)['id']
    #   # using get method of rule group to get a valid rule_group id
    #   get 'api/rule_groups'
    #   p_body = JSON.parse(last_response.body)
    #   id_2 = JSON.parse((p_body[0]).to_json)['id']
    #   # passing valid container_group id and rule_group id array
    #   post 'api/container_groups/' + id_1, [id_2].to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(204)
    #   # passing invalid container_group id and valid rule_group id array
    #   post 'api/container_groups/' + 'we345678', [id_2].to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(404)
    #   # passing empty array in body
    #   post 'api/container_groups/' + id_1 , [].to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(400)
    #   # passing empty  body
    #   post 'api/container_groups/' + id_1
    #   expect(last_response.status).to eql(400)
    # end

    # it 'will add a container(s) to a container group' do
    #   # get container group id
    #   get 'api/container_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   id_1 = JSON.parse((body[0]).to_json)['id']
    #   # getting 2 valid container ids
    #   get 'api/containers'
    #   body_sys = JSON.parse(last_response.body)
    #   container_id = JSON.parse((body_sys[0]).to_json)['id']
    #   container_id1 = JSON.parse((body_sys[1]).to_json)['id']
    #   # passing correct params
    #   post 'api/container_groups/' + id_1 + '/members', [container_id, container_id1].to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(204)
    #   # passing invalid containerGroup id
    #   id_2 = '0oi8u7'
    #   post 'api/container_groups/' + id_1 + '/members', [id_2].to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(400)
    #   # passing invalid container group id
    #   get 'api/container_groups/12345tygh/members'
    #   expect(last_response.status).to eql(404)
    # end

    # it 'will list the container group members' do
    #   get 'api/container_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   id_1 = JSON.parse((body[0]).to_json)['id']
    #   # passing correct parameters
    #   get 'api/container_groups/' + id_1 + '/members'
    #   expect(last_response.status).to eql(200)
    #   # passing invalid container group id
    #   get 'api/container_groups/12345tygh/members'
    #   expect(last_response.status).to eql(404)
    # end

    # it 'will remove a container from a container group' do
    #   # get container group id
    #   get 'api/container_groups'
    #   body = JSON.parse(last_response.body)
    #   # this id has containers as we have added a container in the above block
    #   id_1 = JSON.parse((body[0]).to_json)['id']
    #   # passing correct params
    #   get 'api/container_groups/' + id_1 + '/members'
    #   require 'pp'
    #   container_body = JSON.parse(last_response.body)
    #   container_id = JSON.parse((container_body[0]).to_json)['id']
    #   # passing all valid parameters for DELETE api
    #   delete 'api/container_groups/' + id_1 + '/members/' + container_id
    #   expect(last_response.status).to eql(204)
    #   # passing incorrect container group id
    #   delete 'api/container_groups/IamIncorrectId/members/' + container_id
    #   expect(last_response.status).to eql(404)
    #   # passing incorrect container id
    #   delete 'api/container_groups/' + id_1 + '/members/InCorrectContainerId'
    #   expect(last_response.status).to eql(400)
    # end

    # # it 'will show compliance level of a container group' do
    # #   # get container group id
    # #   get 'api/container_groups'
    # #   body = JSON.parse(last_response.body)
    # #   expect(body).to be_a(Array)
    # #   # this id has containers as we have added a container in the above block
    # #   id_1 = JSON.parse((body[0]).to_json)['id']
    # #   get 'api/container_groups/' + id_1 + '/compliance'
    # #   expect(last_response.status).to eql(200)
    # #   # passing incorrect container group id
    # #   id_1 = '12345'
    # #   get 'api/container_groups/' + id_1 + '/compliance'
    # #   expect(last_response.status).to eql(404)
    # # end

    # it 'will create a user  given an identity' do
    #   post 'api/users', { identity: '12345678', fullname: 'Bhairavi' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(201)
    #   expect(JSON.parse(last_response.body)['fullname']).to eql('Bhairavi')
    #   # not passing the mandatory field identity
    #   post 'api/users', { fullname: 'Bhairavi' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(400)
    # end

    # it 'will list the users' do
    #   get 'api/users'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   expect(last_response.status).to eql(200)
    # end

    # it 'will update a user' do
    #   get 'api/users'
    #   body = JSON.parse(last_response.body)
    #   id_1 = JSON.parse((body[0]).to_json)['id']
    #   identity1 = JSON.parse((body[0]).to_json)['identity']
    #   put 'api/users/' + id_1, { identity: identity1, fullname: 'Bhairavi Konwar' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(JSON.parse(last_response.body)['fullname']).to eql('Bhairavi Konwar')
    #   expect(last_response.status).to eql(200)
    #   # passing wrong id
    #   put 'api/users/abc', { identity: identity1, fullname: 'Bhairavi Konwar' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(404)
    # end

    # it 'will show a user given an id ' do
    #   get 'api/users'
    #   body = JSON.parse(last_response.body)
    #   id_1 = JSON.parse((body[0]).to_json)['id']
    #   get 'api/users/' + id_1
    #   expect(last_response.status).to eql(200)
    #   # passing wrong id
    #   get 'api/users/abc'
    #   expect(last_response.status).to eql(404)
    # end

    # it 'will delete a user given an id ' do
    #   get 'api/users'
    #   body = JSON.parse(last_response.body)
    #   id_1 = JSON.parse((body[0]).to_json)['id']
    #   delete 'api/users/' + id_1
    #   expect(last_response.status).to eql(204)
    #   # passing wrong id
    #   delete 'api/users/abc'
    #   expect(last_response.status).to eql(404)
    # end


    # # Tests for rule_groups APIs

    # # 1. Tests for POST API i.e. post /api/rule_groups

    # it 'will create a new rule group given a name' do
    #   post '/api/rule_groups', { name: 'mytestgroup' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(201)
    #   expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup')

    #   post '/api/rule_groups', { name: 'mytestgroup1' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(201)
    #   expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup1')

    #   post '/api/rule_groups', { name: 'mytestgroup2' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(201)
    #   expect(JSON.parse(last_response.body)['name']).to eql('mytestgroup2')

    #   post '/api/rule_groups'
    #   expect(last_response.status).to eql(400)

    # end

    # # 2. Tests for GET API i.e. get /api/rule_groups

    # it 'will list the rule groups' do
    #   get '/api/rule_groups'
    #   expect(last_response.status).to eql(200)
    # end

    # it 'will return a rule group with a range' do
    #   header 'Range', 'items=1-2'
    #   get '/api/rule_groups'
    #   expect(last_response.status).to eql(206)
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    # end

    # # 3. Tests for PUT API i.e. put /api/rule_groups/{id}

    # it 'will update a rule group with provided id' do
    #   get '/api/rule_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   id_1 = JSON.parse((body[1]).to_json)['id']

    #   rule_group = SentinelDocker::Models::RuleGroup.new(name: 'rule group1')
    #   rule_group.save

    #   put '/api/rule_groups/' + id_1, { name: 'Updated_Rule_Name' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(200)
    #   expect(JSON.parse(last_response.body)['name']).to eql('Updated_Rule_Name')

    #   put '/api/rule_groups/' + id_1, { name: 'Updated_Rule_Name' }.to_json
    #   expect(last_response.status).to eql(400)

    #   put '/api/rule_groups/xyz', { name: 'Updated_Rule_Name' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(404)

    # end

    # # 4. Tests for GET API i.e. get /api/rule_groups/{id}

    # it 'will return a rule group with provided id' do
    #   get '/api/rule_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   id_1 = JSON.parse((body[1]).to_json)['id']
    #   rule_name_1 = JSON.parse((body[1]).to_json)['name']

    #   get '/api/rule_groups/' + id_1
    #   expect(last_response.status).to eql(200)
    #   expect(JSON.parse(last_response.body)['name']).to eql(rule_name_1)

    #   get '/api/rule_groups/xyz'
    #   expect(last_response.status).to eql(404)

    # end

    # # 5. Tests for DELETE API i.e. delete /api/rule_groups/{id}

    # it 'will delete a rule group with provided id' do
    #   get '/api/rule_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   id_1 = JSON.parse((body[1]).to_json)['id']
    #   size = body.size

    #   delete '/api/rule_groups/xyz'
    #   expect(last_response.status).to eql(404)
    #   get '/api/rule_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   expect(body.size).to eql(size)

    #   delete '/api/rule_groups/' + id_1
    #   expect(last_response.status).to eql(204)
    #   get '/api/rule_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   expect(body.size).to eql(size - 1)

    # end

    # # 6. Tests for GET API i.e. get /api/rule_groups/{id}/members
    # it 'will list the rule group members of given id' do
    #   get '/api/rule_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   id_1 = JSON.parse((body[1]).to_json)['id']

    #   get '/api/rule_groups/' + id_1 + '/members'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)

    #   get '/api/rule_groups/xyz/members'
    #   expect(last_response.status).to eql(404)

    # end

    # # 7. Tests for POST API i.e. post/rule_group/{id}/members
    # it 'will add rules to the rule group with given id' do
    #   get '/api/rule_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   id_1 = JSON.parse((body[0]).to_json)['id']

    #   rule_1 = SentinelDocker::Models::Rule.new(name: 'Rule_test1')
    #   rule_1.save
    #   id_4 = rule_1.id
    #   rule_2 = SentinelDocker::Models::Rule.new(name: 'Rule_test2')
    #   rule_2.save
    #   rule_3 = SentinelDocker::Models::Rule.new(name: 'Rule_test3')
    #   rule_3.save

    #   post '/api/rule_groups/' + id_1 + '/members', [id_4].to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(204)

    #   # bad request with invalid rule_id array
    #   post '/api/rule_groups/' + id_1 + '/members', ['id5'].to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(400)

    #   post '/api/rule_groups/xyz/members' , [id_4].to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(404)

    # end

    # # 8. Tests for DELETE API i.e. delete /api/rule_groups/{id}/members/{rule_id}
    # it 'will delete rule with rule id from rule group' do

    #   get '/api/rule_groups'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   id_1 = JSON.parse((body[0]).to_json)['id']

    #   get '/api/rule_groups/' + id_1 + '/members'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   rule_id = JSON.parse((body[0]).to_json)['id']

    #   delete '/api/rule_groups/' + id_1 + '/members/' + rule_id
    #   expect(last_response.status).to eql(204)

    #   delete '/api/rule_groups/' + id_1 + '/members/xyz'
    #   expect(last_response.status).to eql(400)

    #   delete '/api/rule_groups/xyz/members/abc'
    #   expect(last_response.status).to eql(404)

    # end

    # # Tests for rules APIS
    # # 1. Test for GET API i.e. get /api/rules
    # it 'will give the list of rules' do

    #   get '/api/rules'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   expect(last_response.status).to eql(200)

    # end

    # it 'will return a rules given a range' do

    #   header 'Range', 'items=1-2'
    #   get '/api/rules'
    #   expect(last_response.status).to eql(206)

    # end

    # # 2. Test for PUT API i.e. put /api/rules/{id}
    # it 'will update the rule given an id' do

    #   get '/api/rules'
    #   body = JSON.parse(last_response.body)
    #   expect(body).to be_a(Array)
    #   rule_id = JSON.parse((body[0]).to_json)['id']

    #   put '/api/rules/' + rule_id, { grace_period: 30 }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(200)
    #   expect(JSON.parse(last_response.body)['grace_period']).to eql(30)

    #   put '/api/rules/' + rule_id, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(400)

    #   put '/api/rules/xyz', { description: 'rule_updated' }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(404)
    # end

    # # 3. Test for GET API i.e. /api/rules/{id}
    # it 'will return polict given an id' do
    #   rule_5 = SentinelDocker::Models::Rule.new(name: 'Rule_test5')
    #   rule_5.save

    #   get '/api/rules/' + rule_5.id
    #   expect(last_response.status).to eql(200)
    #   expect(JSON.parse(last_response.body)['name']).to eql('Rule_test5')

    #   get '/api/rules/xyz'
    #   expect(last_response.status).to eql(404)
    # end

    # # 4. Test for GET API i.e. /api/rules/{id}/parameters
    # it 'will return polict given an id' do
    #   rule_6 = SentinelDocker::Models::Rule.new(name: 'Rule_test6', description: 'This is test rule')
    #   rule_6.save

    #   get '/api/rules/' + rule_6.id + '/parameters'
    #   expect(last_response.status).to eql(200)

    #   get '/api/rules/xyz/parameters'
    #   expect(last_response.status).to eql(404)

    # end

    after :all do
      SentinelDocker::Store.indices.delete index: 'api_testing'
    end
  end
