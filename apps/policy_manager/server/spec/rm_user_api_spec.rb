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

describe '/api/users' do

  let(:test_data) { {} }
  let(:hash_table) { {} }

  subject { SentinelDocker::API::Root }


  def app
    subject
  end

  def call_post_tenant(opt={})

    conf = opt[:conf] || {}
    identity = opt[:user] || ""
    post 'api/tenants', conf.to_json, 'CONTENT_TYPE' => 'application/json','rack.session' => {'identity' => identity}

  end

  def call_post_user(opt={})

    conf = opt[:conf] || {}
    tenant_param = opt[:tenant] ? "?tenant=#{opt[:tenant]}" : ""
    identity = opt[:user] || ""

    post 'api/users'+tenant_param, conf.to_json, 'CONTENT_TYPE' => 'application/json','rack.session' => {'identity' => identity}

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

  def call_get_users(opt={})
    tenant_param = opt[:tenant] ? "?tenant=#{opt[:tenant]}" : ""
    identity = opt[:user] || ""
    get 'api/users'+tenant_param, {}, 'rack.session' => {'identity' => identity}
  end

  def call_get_user(opt={})
    id = opt[:id]
    tenant_param = opt[:tenant] ? "?tenant=#{opt[:tenant]}" : ""
    identity = opt[:user] || ""
    get 'api/users'+"/#{id}"+tenant_param, {}, 'rack.session' => {'identity' => identity}
  end

  def call_put_user(opt={})
    id = opt[:id]
    conf = opt[:conf] || {}
    tenant_param = opt[:tenant] ? "?tenant=#{opt[:tenant]}" : ""
    identity = opt[:user] || ""
    put 'api/users'+"/#{id}"+tenant_param, conf, 'CONTENT_TYPE' => 'application/json', 'rack.session' => {'identity' => identity}
  end

  def call_delete_user(opt={})
    call_delete(:user, opt)
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

  def called_post_tenant_successfully(tenant_name)
    expect(last_response.status).to eql(201)
    expect(JSON.parse(last_response.body)['id']).not_to be_nil
    expect(JSON.parse(last_response.body)['name']).to eql(tenant_name)
  end

  def called_post_user_successfully(user_name, tenant_id)
    puts "user_name=#{user_name}, tenant_id=#{tenant_id}"
    expect(last_response.status).to eql(201)
    puts "last_response=#{last_response.body}"
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

  it 'will create a user', skip_before: true do

    data = create_test_data('tenant_a', 'admin_a', (0...5).map{|i| "rule#{i}"})
    test_data.merge!(data)

    data = create_test_data('tenant_b', 'admin_b', (0...5).map{|i| "rule#{i}"})

    # fail by tenant 
    call_post_user(conf: {identity: 'admin_t', tenant_id: test_data[:tenant]['id']}, user: test_data[:user]['identity'])
    expect(last_response.status).to eql(403)

    # fail for existing identity (by ibm_admin, even if it belongs to another tenant)
    call_post_user(conf: {identity: data[:user]['identity'], tenant_id: test_data[:tenant]['id']}, user: 'ibm_admin')
    expect(last_response.status).to eql(400)


    # fail by tenant even with explicit tenant_id
    call_post_user(conf: {identity: 'admin_a2', tenant_id: test_data[:tenant]['id']}, user: test_data[:user]['identity'])
    expect(last_response.status).to eql(403)

    # fail when empty identity
    call_post_user(conf: {identity: '', tenant_id: test_data[:tenant]['id']}, user: 'ibm_admin')
    expect(last_response.status).to eql(400)

    # fail when no tenant_id
    call_post_user(conf: {identity: 'admin_a3'}, user: 'ibm_admin')
    expect(last_response.status).to eql(400)

    # fail when empty tenant_id
    call_post_user(conf: {identity: 'admin_a4', tenant_id: ''}, user: 'ibm_admin')
    expect(last_response.status).to eql(400)


  end

  it 'will show a user with a given id' do

    call_get_user(id: test_data[:user]['id'], tenant: test_data[:tenant]['name'], user: 'ibm_admin')
    expect(last_response.ok?).to be(true)
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)['identity']).to eql(test_data[:user]['identity'])

    call_get_user(id: test_data[:user]['id'], user: test_data[:user]['identity'])
    expect(last_response.ok?).to be(true)
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)['identity']).to eql(test_data[:user]['identity'])

    call_get_user(id: 'dummy_id', tenant: test_data[:tenant]['name'], user: 'ibm_admin')
    expect(last_response.ok?).to be(false)
    expect(last_response.status).to eql(404)

  end

  it 'will list users' do


    call_post_user(conf: {identity: 'admin_b', tenant_id: test_data[:tenant]['id']}, user: 'ibm_admin')
    called_post_user_successfully('admin_b', test_data[:tenant]['id'])
    call_post_user(conf: {identity: 'admin_c', tenant_id: test_data[:tenant]['id']}, user: 'ibm_admin')
    called_post_user_successfully('admin_c', test_data[:tenant]['id'])

    # access users in an tenant by ibm_admin
    call_get_users(tenant: test_data[:tenant]['name'], user: 'ibm_admin')
    expect(last_response.ok?).to be(true)
    expect(last_response.status).to eql(200)
    puts "body = #{last_response.body}"
    expect(JSON.parse(last_response.body)).to be_a(Array)
    expect(JSON.parse(last_response.body).size).to eql(3)
    expect(JSON.parse(last_response.body)[0]['id']).to be(test_data[:user]['id'])

    # access users in an tenant by a tenant admin
    call_get_users(user: test_data[:user]['identity'])
    expect(last_response.ok?).to be(true)
    expect(last_response.status).to eql(200)
    expect(JSON.parse(last_response.body)).to be_a(Array)
    expect(JSON.parse(last_response.body).size).to eql(3)
    expect(JSON.parse(last_response.body)[0]['id']).to be(test_data[:user]['id'])

  end

  it 'will list users according to a "Range: items=n-m" header' do

    call_post_user(conf: {identity: 'admin_b', tenant_id: test_data[:tenant]['id']}, user: 'ibm_admin')
    call_post_user(conf: {identity: 'admin_c', tenant_id: test_data[:tenant]['id']}, user: 'ibm_admin')

    call_get_users(user: test_data[:user]['identity'])
    content_range = last_response.headers['Content-Range']
    expect(content_range).to be_a(String)
    expect(content_range).to eq("items 1-3/3")
    expect(JSON.parse(last_response.body)).to be_a(Array)
    expect(JSON.parse(last_response.body).size).to eql(3)
    identity = JSON.parse(last_response.body)[1]['identity']
    header 'Range', "items=2-2"
    call_get_users(user: test_data[:user]['identity'])
    content_range = last_response.headers['Content-Range']
    expect(content_range).to eq("items 2-2/3")
    expect(JSON.parse(last_response.body)).to be_a(Array)
    expect(JSON.parse(last_response.body).size).to eql(1)
    expect(JSON.parse(last_response.body)[0]['identity']).to be(identity)

  end

  it 'will update a user with put' do

    call_post_user(conf: {identity: 'user_b', tenant_id: test_data[:tenant]['id']}, user: 'ibm_admin')
    id = JSON.parse(last_response.body)['id']

    tenant_identity = test_data[:user]['identity']

    ['ibm_admin', tenant_identity].each do |user|

      call_put_user(id: id, conf: {email: 'test@ibm.com'}.to_json, user: user)
      expect(last_response.status).to eql(200)

      call_get_user(id: id, user: tenant_identity)
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['email']).to eq('test@ibm.com')

      call_put_user(id: id, conf: {email: 'test2@ibm.com'}.to_json, user: user)
      expect(last_response.status).to eql(200)

      call_get_user(id: id, user: tenant_identity)
      expect(last_response.ok?).to be(true)
      expect(last_response.status).to eql(200)
      expect(JSON.parse(last_response.body)['email']).to eq('test2@ibm.com')

      # fail when wrong id
      call_put_user(id: 'dummy_id', conf: {email: 'test3@ibm.com'}.to_json, user: user)
      expect(last_response.status).to eql(404)

      # fail when empty id
      call_put_user(id: '', conf: {email: 'test4@ibm.com'}.to_json, user: user)
      expect(last_response.status).to eql(404)

      # fail when trying to update wrong attribute
      call_put_user(id: id, conf: {param1: 'value1'}.to_json, user: user)
      expect(last_response.status).to eql(404)

      # fail when trying to update unauthorized attribute
      call_put_user(id: id, conf: {api_key: 'value1'}.to_json, user: user)
      expect(last_response.status).to eql(404)

      # conf must be json
      call_put_user(id: id, conf: 'xxxxxxyyyyy', user: user)
      expect(last_response.status).to eql(400)

    end

  end

  it 'will delete a user with a given id', skip_after: true  do

    call_post_user(conf: {identity: 'user_b', tenant_id: test_data[:tenant]['id']}, user: 'ibm_admin')
    id = JSON.parse(last_response.body)['id']

    tenant_identity = test_data[:user]['identity']

    ['ibm_admin', tenant_identity].each do |user|

      call_delete_user(id: id, user: test_data[:user]['identity'])
      expect(last_response.status).to eql(403)

      call_delete_user(id: id, user: 'ibm_admin')
      expect(last_response.status).to eql(204)

      call_delete_user(id: 'dummy_id', user: 'ibm_admin')
      expect(last_response.status).to eql(404)

      call_delete_user(id: '', user: 'ibm_admin')
      expect(last_response.status).to eql(405)

      call_delete_tenant(id: test_data[:tenant]['id'], user: 'ibm_admin')
      expect(last_response.status).to eql(204)

    end

  end

  after :all do
#    SentinelDocker::Store.indices.delete index: 'api_testing'
  end
end
