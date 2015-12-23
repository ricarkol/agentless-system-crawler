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

describe '/api/rules' do

  let(:test_data) { {} }
  let(:hash_table) { {} }

  subject { SentinelDocker::API::Root }


  def app
    subject
  end

  def call_post_rule(opt={})

    conf = opt[:conf] || {}
    tenant_param = opt[:tenant] ? "?tenant=#{opt[:tenant]}" : ""
    identity = opt[:user] || ""

    temp_dir = Dir.mktmpdir
    begin
      File.write(File.join(temp_dir, 'metadata.json'), conf.to_json)
      f = Tempfile.new(['rule','.zip'])
      path = f.path
      f.close(true)
      out = `zip #{path} -9 -j #{temp_dir}/*`
      post 'api/rules'+tenant_param, {'rule_zip' => Rack::Test::UploadedFile.new(path, 'application/zip', true)}, {'rack.session' => {'identity' => identity}}
      if last_response.body
        id = JSON.parse(last_response.body)['id']
        hash_table[id] = Digest::MD5.hexdigest(File.open(path,'rb').read)
      end
    rescue => e
      puts e.backtrace.join("\n")
    ensure
      FileUtils.remove_entry_secure temp_dir
    end

  end

  def call_post_tenant(opt={})

    conf = opt[:conf] || {}
    identity = opt[:user] || ""
    post 'api/tenants', conf.to_json, 'CONTENT_TYPE' => 'application/json','rack.session' => {'identity' => identity}

  end

  def call_post_user(opt={})

    conf = opt[:conf] || {}
    identity = opt[:user] || ""

    post 'api/users', conf.to_json, 'CONTENT_TYPE' => 'application/json','rack.session' => {'identity' => identity}

  end

  def call_get_rules(opt={})
    tenant_param = opt[:tenant] ? "?tenant=#{opt[:tenant]}" : ""
    identity = opt[:user] || ""
    get 'api/rules'+tenant_param, {}, 'rack.session' => {'identity' => identity}
  end

  def call_get_rule(opt={})
    id = opt[:id]
    tenant_param = opt[:tenant] ? "?tenant=#{opt[:tenant]}" : ""
    identity = opt[:user] || ""
    get 'api/rules'+"/#{id}"+tenant_param, {}, 'rack.session' => {'identity' => identity}
  end

  def call_get_rule_files(opt={})
    id = opt[:id]
    tenant_param = opt[:tenant] ? "?tenant=#{opt[:tenant]}" : ""
    identity = opt[:user] || ""
    get 'api/rules'+"/#{id}/files"+tenant_param, {}, 'rack.session' => {'identity' => identity}
  end

  def call_put_rule(opt={})
    id = opt[:id]
    conf = opt[:conf] || {}
    tenant_param = opt[:tenant] ? "?tenant=#{opt[:tenant]}" : ""
    identity = opt[:user] || ""
    put 'api/rules'+"/#{id}"+tenant_param, conf, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => identity}
  end

  def call_delete_rule(opt={})
    call_delete(:rule, opt)
  end

  def call_delete_rules(opt={})
    ids = opt[:ids]
    tenant_param = opt[:tenant] ? "?tenant=#{opt[:tenant]}" : ""
    identity = opt[:user] || ""
    delete "api/rules/bulk_delete" +tenant_param, ids.to_json, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => identity}
  end

  def call_delete_tenant(opt={})
    call_delete(:tenant, opt)
  end

  def call_delete(type, opt={})
    id = opt[:id]
    tenant_param = type != :tenant && opt[:tenant] ? "?tenant=#{opt[:tenant]}" : ""
    identity = opt[:user] || ""
    delete "api/#{type.to_s.pluralize}/" + id+tenant_param, {}, 'rack.session' => {'identity' => identity}
  end

  before :all do
    begin
      SentinelDocker::Store.indices.create index: 'api_testing'
    rescue
      puts 'Index not created. Already existed.'
    end
    SentinelDocker::Config.db.index_name = 'api_testing'

    # test_data = {}

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

  before do |example|
    unless example.metadata[:skip_before] 
      data = create_test_data('tenant_a', 'admin_a', (0...5).map{|i| "rule#{i}"})
      test_data.merge!(data)
    end
  end

  after do |example|
    unless example.metadata[:skip_after] 
      delete_test_data(test_data[:tenant]['id'])
      test_data.clear
    end
  end

  # common_before (create tenant and admin)
  # common_rules (create 5 rules for the group)
  #create tenant tenant_a by ibm_admin
  #create user admin_a for tenant_a by ibm_admin
  #create 5 rules for tenant a (rule0 by ibm_admin and rule1-4 by admin_a)

  def called_post_tenant_successfully(tenant_name)
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['id']).not_to be_nil
    expect(JSON.parse(last_response.body)['name']).to eql(tenant_name)
  end

  def called_post_user_successfully(user_name, tenant_id)
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['id']).not_to be_nil
    expect(JSON.parse(last_response.body)['identity']).to eq(user_name)
    expect(JSON.parse(last_response.body)['tenant_id']).to eql(tenant_id)
  end

  def called_post_rule_successfully(rule_name, tenant_id)
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['id']).not_to be_nil
    expect(JSON.parse(last_response.body)['name']).to eql(rule_name)
    expect(JSON.parse(last_response.body)['tenant_id']).to eql(tenant_id)
  end

  def called_get_rule_successfully(id, rule_name, tenant_name)
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['id']).to eql(id)
    expect(JSON.parse(last_response.body)['name']).to eql(rule_name)
    expect(JSON.parse(last_response.body)['tenant_id']).to eql(tenant_id)
  end

  def called_delete_tenant_successfully(id)
    expect(last_response.status).to eql(204)
  end

  def create_test_data(tenant_name, user_name, rule_names=[]) 

    call_post_tenant(conf: { name: tenant_name }, user: 'ibm_admin')
    called_post_tenant_successfully(tenant_name)

    tenant = JSON.parse(last_response.body)
    tenant_id = tenant['id']

    call_post_user(conf: {identity: user_name, tenant_id: tenant_id}, user: 'ibm_admin')
    called_post_user_successfully(user_name, tenant_id)
    user = JSON.parse(last_response.body)

    rules = {}
    (0...5).each do |i|
      rule_name = "rule#{i}"
      if i==0
        call_post_rule(conf: { name: rule_name }, tenant: tenant['name'], user: 'ibm_admin')
      else
        call_post_rule(conf: { name: rule_name }, user: user['identity'])
      end
      called_post_rule_successfully(rule_name, tenant_id)
      rules[JSON.parse(last_response.body)['id']] = JSON.parse(last_response.body)
    end

    {tenant: tenant, user: user, rules: rules}

  end

  def delete_test_data(id) 
    call_delete_tenant(id: id, user: 'ibm_admin')
    called_delete_tenant_successfully(id)
  end

  it 'will create a rule', skip_before: true do 

    data = create_test_data('tenant_a', 'admin_a', (0...5).map{|i| "rule#{i}"})
    test_data.merge!(data)

    call_post_rule(conf: { name: test_data[:rules].values[0]['name'] }, user: test_data[:user]['identity'])
    expect(last_response.status).to eql(400)

    call_post_rule(conf: { name: '' }, user: test_data[:user]['identity'])
    expect(last_response.status).to eql(400)

  end

  # it 'will create a rule' do

  #   tenant_name = 'tenant_a'
  #   call_post_tenant(conf: { name: tenant_name }, user: 'ibm_admin')
  #   expect(last_response.status).to eql(201)
  #   expect(JSON.parse(last_response.body)['id']).not_to be_nil
  #   expect(JSON.parse(last_response.body)['name']).to eql(tenant_name)
  #   test_data[:tenant] = JSON.parse(last_response.body)
  #   tenant_id = test_data[:tenant]['id']

  #   user_name = 'admin_a'
  #   call_post_user(conf: {identity: user_name, tenant_id: tenant_id}, user: 'ibm_admin')
  #   expect(last_response.status).to eql(201)
  #   expect(JSON.parse(last_response.body)['id']).not_to be_nil
  #   expect(JSON.parse(last_response.body)['identity']).to eq(user_name)
  #   expect(JSON.parse(last_response.body)['tenant_id']).to eql(tenant_id)
  #   test_data[:user] = JSON.parse(last_response.body)

  #   rules = {}
  #   (0...5).each do |i|

  #     conf = { name: "rule#{i}" }

  #     if i==0
  #       call_post_rule(conf: conf, tenant: test_data[:tenant]['name'], user: 'ibm_admin')
  #     else
  #       call_post_rule(conf: conf, user: test_data[:user]['identity'])
  #     end
  #     expect(last_response.status).to eql(201)
  #     expect(JSON.parse(last_response.body)['id']).not_to be_nil
  #     expect(JSON.parse(last_response.body)['name']).to eql(conf[:name])
  #     rules[JSON.parse(last_response.body)['id']] = JSON.parse(last_response.body)

  #   end
  #   test_data[:rules] = rules

  #   call_post_rule(conf: { name: test_data[:rules].values[0]['name'] }, user: test_data[:user]['identity'])
  #   expect(last_response.status).to eql(400)

  #   call_post_rule(conf: { name: '' }, user: test_data[:user]['identity'])
  #   expect(last_response.status).to eql(400)

  # end

  it 'will show a rule with a given id' do

    test_data[:rules].each do |id, rule|
      call_get_rule(id: id, tenant: test_data[:tenant]['name'], user: 'ibm_admin')
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['name']).to eql(rule['name'])

      call_get_rule(id: id, user: test_data[:user]['identity'])
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['name']).to eql(rule['name'])

    end

    call_get_rule(id: 'dummy_id', tenant: test_data[:tenant]['name'], user: 'ibm_admin')
    expect(last_response.ok?).to be(false)
    expect(last_response.status).to eql(404)

  end

  it 'will list rules' do

    # access rules in an tenant by ibm_admin
    call_get_rules(tenant: test_data[:tenant]['name'], user: 'ibm_admin')
    expect(last_response.ok?).to be(true)
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)).to be_a(Array)
    expect(JSON.parse(last_response.body).size).to eql(test_data[:rules].size)
    JSON.parse(last_response.body).each do |r|
      expect(test_data[:rules].has_key? r['id']).to be(true)
    end

    # access rules in an tenant by a tenant admin
    call_get_rules(user: test_data[:user]['identity'])
    expect(last_response.ok?).to be(true)
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)).to be_a(Array)
    expect(JSON.parse(last_response.body).size).to eql(test_data[:rules].size)
    JSON.parse(last_response.body).each do |r|
      expect(test_data[:rules].has_key? r['id']).to be(true)
    end

  end

  it 'will list rules according to a "Range: items=n-m" header' do
    rules = test_data[:rules]
    call_get_rules(user: test_data[:user]['identity'])
    content_range = last_response.headers['Content-Range']
    expect(content_range).to be_a(String)
    expect(content_range).to eq("items 1-#{rules.size}/#{rules.size}")
    header 'Range', "items=2-#{rules.size-1}"
    call_get_rules(user: test_data[:user]['identity'])
    content_range = last_response.headers['Content-Range']
    expect(content_range).to eq("items 2-#{rules.size-1}/#{rules.size}")
  end

  it 'will update a rule with put' do
    rules = test_data[:rules]
    rules.each do |id, name|
      call_put_rule(id: id, conf: {parameters: {key: 'value'}}.to_json, user: test_data[:user]['identity'])
      expect(last_response.status).to eql(200)

      call_get_rule(id: id, user: test_data[:user]['identity'])
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['parameters']).to be_a(Hash)
      expect(JSON.parse(last_response.body)['parameters']['key']).to eq('value')
    end

    call_put_rule(id: 'dummy_id', conf: {parameters: {key: 'value'}}.to_json, user: test_data[:user]['identity'])
    expect(last_response.status).to eql(404)

    call_put_rule(id: '', conf: {parameters: {key: 'value'}}.to_json, user: test_data[:user]['identity'])
    expect(last_response.status).to eql(405)

    call_put_rule(id: rules.keys[0], conf: 'xxxxxxyyyyy', user: test_data[:user]['identity'])
    expect(last_response.status).to eql(400)

  end

  it 'will delete a rule with a given id', skip_after: true  do

    rules = test_data[:rules]
    rule_ids = rules.keys
    rule_ids.each do |id|
      call_delete_rule(id: id, user: test_data[:user]['identity'])
      expect(last_response.status).to eql(204)
      rules.delete(id)
    end
    test_data[:rules] = rules

    call_delete_rule(id: 'dummy_id', user: test_data[:user]['identity'])
    expect(last_response.status).to eql(404)

    call_delete_rule(id: '', user: test_data[:user]['identity'])
    expect(last_response.status).to eql(405)

    call_delete_tenant(id: test_data[:tenant]['id'], user: 'ibm_admin')
    expect(last_response.status).to eql(204)

  end

  it 'will allow only show its own rule by a user', skip_before: true, skip_after: true do

    users = {}
    test_data_array = []
    (0...2).each do |i|

      tenant_name = "tenant#{i}"
      call_post_tenant(conf: { name: tenant_name }, user: 'ibm_admin')
      expect(last_response.status).to eql(201)
      expect(JSON.parse(last_response.body)['id']).not_to be_nil
      expect(JSON.parse(last_response.body)['name']).to eql(tenant_name)
      tenant_id = JSON.parse(last_response.body)['id']
      test_data_l = { tenant: JSON.parse(last_response.body) }

      identity = "admin_#{i}"
      call_post_user(conf: {identity: identity, tenant_id: tenant_id}, user: 'ibm_admin')
      expect(last_response.status).to eql(201)
      expect(JSON.parse(last_response.body)['id']).not_to be_nil
      expect(JSON.parse(last_response.body)['identity']).to eq(identity)
      expect(JSON.parse(last_response.body)['tenant_id']).to eql(tenant_id)
      test_data_l[:user] = JSON.parse(last_response.body)

      rule_name = "rule#{i}"
      call_post_rule(conf: { name: rule_name }, user:  test_data_l[:user]['identity'])
      expect(last_response.status).to eql(201)
      expect(JSON.parse(last_response.body)['id']).not_to be_nil
      expect(JSON.parse(last_response.body)['name']).to eql(rule_name)
      test_data_l[:rule] = JSON.parse(last_response.body)
      test_data_array << test_data_l

    end

    test_data_array.each do |test_data_l|

      id = test_data_l[:rule]['id']

      call_get_rule(id: id, user: 'ibm_admin')
      expect(last_response.ok?).to be(false)
      expect(last_response.status).to eql(404)

      call_get_rule(id: id, tenant: test_data_l[:tenant]['name'], user: 'ibm_admin')
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['name']).to eql(test_data_l[:rule]['name'])

    end

    # allow to get user's own rule
    test_data_array.each do |test_data_1|
      user = test_data_1[:user]
      tenant1 = test_data_1[:tenant]
      rule1 = test_data_1[:rule]
      test_data_array.each do |test_data_2|
        rule2 = test_data_2[:rule]
        tenant2 = test_data_2[:tenant]
        if tenant1['id'] == tenant2['id']
          call_get_rule(id: rule2['id'], user: user['identity'])
          expect(last_response.ok?).to be(true)
          expect(last_response.status).to eql(200)
          expect(JSON.parse(last_response.body)['name']).to eql(rule2['name'])

          call_get_rules(user: user['identity'])
          expect(last_response.ok?).to be(true)
          expect(last_response.status).to eql(200)
          expect(JSON.parse(last_response.body)).to be_a(Array)
          expect(JSON.parse(last_response.body).size).to eql(1)

          call_put_rule(id: rule2['id'], conf: { description: 'desc' }.to_json, user: user['identity'])
          expect(last_response.ok?).to be(true)
          expect(last_response.status).to eql(200)

        else
          call_get_rule(id: rule2['id'], user: user['identity'])
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

          call_get_rule(id: rule2['id'], tenant: tenant2['name'], user: user['identity'])
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

          call_get_rules(tenant: tenant2['name'], user: user['identity'])
          expect(last_response.ok?).to be(true)
          expect(last_response.status).to eql(200)
          expect(JSON.parse(last_response.body)).to be_a(Array)
          expect(JSON.parse(last_response.body).size).to eql(1)
          expect(JSON.parse(last_response.body).select {|g| g['id']==rule1['id']}.empty?).to be(false)

          call_put_rule(id: rule2['id'], conf: { description: 'desc' }.to_json, user: user['identity'])
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

          call_put_rule(id: rule2['id'], conf: { description: 'desc' }.to_json, tenant: tenant2['name'], user: user['identity'])
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

          call_delete_rule(id: rule2['id'], user: user['identity'])
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

          call_delete_rule(id: rule2['id'], tenant: tenant2['name'], user: user['identity'])
          expect(last_response.ok?).to be(false)
          expect(last_response.status).to eql(404)

        end

      end
    end

    test_data_array.each do |test_data_1|
      user = test_data_1[:user]
      tenant = test_data_1[:tenant]
      rule = test_data_1[:rule]

      rule_name = "rule_d"
      call_post_rule(conf: { name: rule_name }, user: user['identity'])
      expect(last_response.status).to eql(201)
      expect(JSON.parse(last_response.body)['id']).not_to be_nil
      expect(JSON.parse(last_response.body)['name']).to eql(rule_name)
      new_rule_id = JSON.parse(last_response.body)['id']

      call_get_rule(id: new_rule_id, user: user['identity'])
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['name']).to eq(rule_name)

      call_delete_rule(id: new_rule_id, user: user['identity'])
      expect(last_response.status).to eql(204)

      call_get_rule(id: new_rule_id, user: user['identity'])
      expect(last_response.ok?).to be(false)
      expect(last_response.status).to eql(404)
    end

  end

  # GET /api/rules/{id}/files
  it 'will return a zip file for a rule with a given id' do

    test_data[:rules].each do |id, rule|
      call_get_rule_files(id: id, tenant: test_data[:tenant]['name'], user: 'ibm_admin')
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(last_response.headers['Content-Type']).to eq('application/octet-stream')
      expect(Digest::MD5.hexdigest(last_response.body)).to eq(hash_table[id])

      call_get_rule_files(id: id, user: test_data[:user]['identity'])
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(last_response.headers['Content-Type']).to eq('application/octet-stream')
      expect(Digest::MD5.hexdigest(last_response.body)).to eq(hash_table[id])

    end

    call_get_rule_files(id: 'dummy_id', tenant: test_data[:tenant]['name'], user: 'ibm_admin')
    expect(last_response.ok?).to be(false)
    expect(last_response.status).to eql(404)

    call_get_rule_files(id: test_data[:rules].keys[0], tenant: 'dummy_name', user: 'ibm_admin')
    expect(last_response.ok?).to be(false)
    expect(last_response.status).to eql(403)

  end

  # DELETE /api/rules/bulk_delete Delete rules
  it 'will delete rules with a given list of ids', skip_after: true  do

    rules = test_data[:rules]
    rule_ids = rules.keys
    call_delete_rules(ids: rule_ids, user: test_data[:user]['identity'])
    expect(last_response.status).to eql(204)

    call_get_rules(user: test_data[:user]['identity'])
    expect(last_response.ok?).to be(true)
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)).to be_a(Array)
    expect(JSON.parse(last_response.body).size).to eql(0)

    call_delete_rules(ids: ['dummy_id'], user: test_data[:user]['identity'])
    expect(last_response.status).to eql(404)

    call_delete_rules(ids: [], user: test_data[:user]['identity'])
    expect(last_response.status).to eql(204)

    call_delete_tenant(id: test_data[:tenant]['id'], user: 'ibm_admin')
    expect(last_response.status).to eql(204)

  end

  after :all do
    SentinelDocker::Store.indices.delete index: 'api_testing'
  end
end
