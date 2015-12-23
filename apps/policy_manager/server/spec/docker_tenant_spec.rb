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

include SentinelDocker::Models

describe SentinelDocker::Models do
  before :all do
    begin
      SentinelDocker::Store.indices.create index: 'testing'
    rescue
      puts 'Index not created. Already existed.'
    end
    SentinelDocker::Config.db.index_name = 'testing'

    @rules = []
    @tenants = []
  end


  it 'create default set of rules' do
    (0...10).each do |i|
      rule = Rule.new(name: "rule_#{i}", script_path: "Comp_#{i}.py")
      expect(rule.save).to be(true)
      @rules << rule
    end
  end

  it 'create new tenant' do
    (0...3).each do |i|
      tenant = Tenant.new(name: "tenant_#{i}", namespace: "owner_namespace_#{i}")
      expect(tenant.save).to be(true)
      @tenants << tenant

      (0...2).each do |j|
        rule_assign_group = RuleAssignGroup.new(name: "rule_assign_group_#{j}_for_tenant_#{i}")
        rule_assign_group.tenant_id = tenant.id
        rule_assign_group.rule_id = Rule.all.map do |r|
          r.id
        end
        rule_assign_group.default = true if j == 0
        expect(rule_assign_group.save).to be(true)
        expect(rule_assign_group.rules.size).to be(Rule.all.size)
      end
    end
  end

  it 'get rules for tenant and group' do

    tenant = @tenants.last
    rule_assign_group = tenant.rule_assign_groups.last

    t = Tenant.find(query: { 'name' => tenant.name }).first
    expect(t.id).to eq(tenant.id)

    g = RuleAssignGroup.find(query: { 'tenant_id' => tenant.id, 'name' => rule_assign_group.name }).first
    expect(g).not_to be_nil
    expect(g.id).to eq(rule_assign_group.id)
    expect(g.tenant.id).to eq(tenant.id)

  end

  it 'assign image to rule_assign_group' do

    @tenants.each do |tenant|
      tenant.rule_assign_groups.each do |group|
        image = Image.new(image_id: "image_#{group.name}", image_name: "image_#{group.name}", namespace: "namespace_#{group.name}", created: Time.now.to_i, created_by: "ls -al", created_from: "image0")
        image.belongs_to group
        expect(image.save).to be(true)
        # group.image_id = [image.id]
        # expect(group.save).to be(true)
        image = Image.get(image.id)
        expect(image.image_rules.size).to be(group.rules.size)
        image.image_rules.each do |ir|
          expect(group.rule_id.include? ir.rule.id).to be(true)
        end
      end
    end
  end

  it 'change assignment from one rule_assign_group to other' do

    @tenants.each do |tenant|
      rule_assign_groups = tenant.rule_assign_groups
      group_a = rule_assign_groups.first
      size_a = group_a.images.size
      group_b = rule_assign_groups.last
      size_b = group_b.images.size
      image = group_a.images.first
      image.belongs_to group_b
      expect(image.save).to be(true)
      expect(group_a.images.size).to be(size_a-1)
      group_b.images << image
      expect(group_b.save).to be(true)
      expect(group_b.images.size).to be(size_b+1)
      expect(image.image_rules.size).to be(group_b.rules.size)
      image.image_rules.each do |ir|
        expect(group_b.rule_id.include? ir.rule.id).to be(true)
      end

    end

  end

  after :all do
    SentinelDocker::Store.indices.delete index: 'testing'
    sleep(3)
  end

end
