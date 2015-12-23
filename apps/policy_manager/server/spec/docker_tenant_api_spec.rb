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

    @namespaces = {}
    @tenant = nil

   end

  #tenants, rules

  it 'create default set of rules' do
    # (0...10).each do |i|
    #   post 'api/rules', { name: "rule_#{i}", script_path: "Comp_#{i}.py" }.to_json, 'CONTENT_TYPE' => 'application/json'
    #   expect(last_response.status).to eql(201)
    #   expect(JSON.parse(last_response.body)['name']).to eql("rule_#{i}")
    # end
    Dir::glob(File.join('/home/sentinel/test_zips', "*.zip")).each do |f|
      post 'api/rules', "rule_zip" => Rack::Test::UploadedFile.new(f), 'CONTENT_TYPE' => 'application/zip'
      expect(last_response.status).to eql(201)
      break
    end

#     (0...10).each do |i|
#       rule = Rule.new(name: "rule_#{i}", script_path: "Comp_#{i}.py")
# #      puts "error=#{rule.errors.full_messages.join(',')}" unless rule.save
#       expect(rule.save).to be(true)
#     end
  end


  it 'create new tenant' do
    (0...3).each do |i|
      post 'api/tenants', { name: "tenant_#{i}", namespace: "owner_namespace_#{i}" }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eql(201)
      expect(JSON.parse(last_response.body)['name']).to eql("tenant_#{i}")
      expect(JSON.parse(last_response.body)['namespace']).to eql("owner_namespace_#{i}")
      tenant_id = JSON.parse(last_response.body)['id']

      (0...2).each do |j|
        get 'api/rules'
        expect(last_response.status).to eql(200)
        body = JSON.parse(last_response.body)
        expect(body).to be_a(Array)
        rule_ids = body.map do |b|
          b['id']
        end

        get "api/tenants/#{tenant_id}/groups"
        expect(last_response.status).to eql(200)
        body = JSON.parse(last_response.body)
        expect(body).to be_a(Array)
        size = body.size

        default = true if j == 0

        post "api/tenants/#{tenant_id}/groups", { name: "rule_assign_group_#{j}_for_tenant_#{i}",  default: default, rule_id: rule_ids}.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eql(201)

        get "api/tenants/#{tenant_id}/groups"
        expect(last_response.status).to eql(200)
        body = JSON.parse(last_response.body)
        expect(body).to be_a(Array)
        expect(body.size).to be(size+1)

      end
    end
  end

  it 'assign image to rule_assign_group' do

    get "api/tenants"
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    tenants = body
    tenants.each do |tenant|
      get "api/tenants/#{tenant['id']}/groups"
      expect(last_response.status).to eql(200)
      body = JSON.parse(last_response.body)
      expect(body).to be_a(Array)
      rule_assign_groups = body
      rule_assign_groups.each do |rule_assign_group|
        group_name = rule_assign_group['name']

        (0...3).each do |i|
          post "api/images", {image_id: "image#{i}_#{group_name}", rule_assign_group_id: rule_assign_group['id'], image_name: "image#{i}_#{group_name}", namespace: "namespace#{i}_#{group_name}", created: Time.now.to_i, created_by: "ls -al", created_from: "image#{i}"}.to_json, 'CONTENT_TYPE' => 'application/json'
          expect(last_response.status).to eql(201)
          image = JSON.parse(last_response.body)
          expect(image['image_name']).to eql("image#{i}_#{group_name}")
        end
      end
    end


  end

  it 'get rules for tenant and group' do

    get "api/tenants"
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    tenants = body
    tenants.each do |tenant|

      get "api/tenants/#{tenant['id']}/groups"
      expect(last_response.status).to eql(200)
      rule_assign_groups = JSON.parse(last_response.body)
      expect(rule_assign_groups).to be_a(Array)

      rule_assign_groups.each do |rule_assign_group|
        # puts "tenant=#{tenant['name']},group=#{rule_assign_group['name']}"
        output = `curl -s -k -XGET https://localhost:9292/api/get_tenant_rules?tenant=#{tenant['name']}\&group=#{rule_assign_group['name']}`
        # puts "api/get_tenant_rules?tenant=#{tenant['name']}&group=#{rule_assign_group['name']}"
        # get "api/get_tenant_rules?tenant=#{tenant['name']}&group=#{rule_assign_group['name']}"
        # puts "output=#{output}"
        # puts "rule_assign_group=#{rule_assign_group}"
        body = JSON.parse(output)
        expect(body).to be_a(Array) 
        expect(body.size).to eq(rule_assign_group['rule_id'].size)
      end
    end
  end

  it 'update rules in a group for a tenant' do
    
    rule_ids = {}
    get 'api/rules'
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    body.each do |b|
      rule_ids[b['id']]=b['timestamp']
    end


    update = {}

    rule_ids.keys.each_with_index do |id, i|
      if i%2==0
        description = "updated <#{id}>"
        put 'api/rules/' + id, { description: description }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eql(200)
        update[id] = description
      end
    end

    get 'api/rules'
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    body.each do |b|
      expect(b['timestamp']).not_to be_nil
      if update.has_key? b['id']
        expect(update[b['id']]).to eql(b['description'])
        expect(b['timestamp']).to be > rule_ids[b['id']]
      else
        expect(b['timestamp']).to be rule_ids[b['id']]
      end
    end

  end

  it 'get rules for existing images' do

    Image.all.each do |image|
      rules = {}
      image.rule_assign_group.rules.each do |r|
        rules[r.name]=r.timestamp
      end
      expect(@namespaces.has_key? image.namespace).to be(false)
      @namespaces[image.namespace] = rules
    end

    get "api/tenants"
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    tenants = body
    tenants.each do |tenant|

      owner_namespace = tenant['namespace']

      @namespaces.each do |namespace, rules|
        # puts "curl -s -k -XGET https://localhost:9292/api/get_rules?namespace=#{namespace}\&owner_namespace=#{owner_namespace}"
        output = `curl -s -k -XGET 'https://localhost:9292/api/get_rules?namespace=#{namespace}&owner_namespace=#{owner_namespace}'`
        # puts "api/get_tenant_rules?tenant=#{tenant['name']}&group=#{rule_assign_group['name']}"
        # get "api/get_tenant_rules?tenant=#{tenant['name']}&group=#{rule_assign_group['name']}"
        # puts "output=#{output}"
        # puts "rule_assign_group=#{rule_assign_group}"
        body = JSON.parse(output)
        expect(body.size).to eq(rules.size)
        body.each do |k, v|
          expect(v['timestamp']).to be rules[k]
        end

      end

    end

  end

  it 'get default rules for new image' do

    get "api/tenants"
    expect(last_response.status).to eql(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    @tenant = body[0]
    owner_ns = @tenant['namespace']
    new_ns = "new_ns_0"
    output = `curl -s -k -XGET 'https://localhost:9292/api/get_rules?namespace=#{new_ns}&owner_namespace=#{owner_ns}'`

    image = Image.find(query: { 'namespace' => new_ns }).first
    expect(image).not_to be_nil
    expect(image.rule_assign_group.tenant.namespace).to eq(owner_ns)
    expect(image.rule_assign_group.default).to be(true)

  end

  it 'get default rules for new image' do

    new_ns = "new_ns_0"

    image = Image.find(query: { 'namespace' => new_ns }).first
    expect(image).not_to be_nil
    owner_ns = image.rule_assign_group.tenant.namespace
    rule_assign_groups = image.rule_assign_group.tenant.rule_assign_groups

    rule_assign_groups.each do |g|
      put "api/images/#{image.id}", {rule_assign_group_id: g.id}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eql(200)
      output = `curl -s -k -XGET 'https://localhost:9292/api/get_rules?namespace=#{new_ns}&owner_namespace=#{owner_ns}'`
      body = JSON.parse(output)
      expect(body.size).to eq(g.rules.size)
    end

  end

  it 'change default group' do

    new_ns = "new_ns_0"

    image = Image.find(query: { 'namespace' => new_ns }).first
    expect(image).not_to be_nil
    owner_ns = image.rule_assign_group.tenant.namespace
    tenant = image.rule_assign_group.tenant
    rule_assign_groups = tenant.rule_assign_groups

    rule_assign_groups.each do |g|

      https = Net::HTTP.new('localhost', 9292)
      https.use_ssl = true
      https.verify_mode = OpenSSL::SSL::VERIFY_NONE
      req = Net::HTTP::Put.new("/api/set_tenant_rules?tenant=#{tenant.name}\&group=#{g.name}\&default=true", initheader = { 'Content-Type' => 'application/json'})
      req.body = g.rules.map{|r| r.id}.to_json.to_s
      response = https.start {|http| http.request(req) }
      expect(response.code.to_i).to eq(200)

#      output = `echo "curl -s -k -XPUT -d @- https://localhost:9292/api/set_tenant_rules?tenant=#{tenant['name']}\&group=#{rule_assign_group['name']}\&default=true`, g.rules.map{|r| r.id}.to_json, 'CONTENT_TYPE' => 'application/json'

      get "api/tenants/#{tenant.id}/groups"
      expect(last_response.status).to eql(200)
      groups = JSON.parse(last_response.body)
      expect(groups).to be_a(Array)

      groups.each do |g2|
        if g2['id'] == g.id
          expect(g2['default']).to be(true)        
        else
          expect(g2['default']).to be(false)        
        end
      end
    end

  end

  it 'update a rule' do
    #set_rule
    #get_rules
  end

  after :all do
    SentinelDocker::Store.indices.delete index: 'testing'
  end

end
