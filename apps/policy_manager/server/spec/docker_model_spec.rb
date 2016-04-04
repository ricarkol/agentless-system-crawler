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
    @data = {}
  end

  it 'sets an id on save' do
    group = ContainerGroup.new(
      name: 'default', description: 'This is the default group.')
    expect(group.save).to be(true)

    @data[:group_id] = group.id
    expect(group.persisted?).to be(true)
  end

  it 'find results responds to total, offset, and limit method calls' do
    results = ContainerGroup.find
    expect(results.respond_to?(:total)).to be(true)
    expect(results.respond_to?('total='.to_sym)).to be(true)
    expect(results.respond_to?(:offset)).to be(true)
    expect(results.respond_to?('offset='.to_sym)).to be(true)
    expect(results.respond_to?(:limit)).to be(true)
    expect(results.respond_to?('limit='.to_sym)).to be(true)

    expect(results.total).to be(1)
    expect(results.offset).to be(nil)
    expect(results.limit).to be(SentinelDocker::Config.db.limit)
  end

  it 'can be obtained through a get call' do
    group = ContainerGroup.get(@data[:group_id])
    @data[:group] = group
    expect(group).to be_a(ContainerGroup)
    expect(group.id).to eql(@data[:group_id])
  end

  it 'can be deleted' do
    group = @data[:group]
    group.delete
    expect(ContainerGroup.get(group.id)).to be(nil)
    expect(ContainerGroup.find.size).to eql(0)
  end

  it 'creates method for has_many relationship' do
    expect(@data[:group].respond_to?(:containers)).to be(true)
  end

  it 'runs validations specified in the model' do
    group = @data[:group]
    group.name = nil
    expect(group.valid?).to be(false)
  end

  it 'prevents saving a model if it is not valid' do
    group = @data[:group]
    expect(group.save).to be(false)
  end

  it 'serializes attributes even if not specified through constructor' do
    group = ContainerGroup.new(description: 'foobar')
    expect(group.as_json.key?(:name)).to be(true)
  end

  it 'creates method to get all items in a has_many relation' do
    group = @data[:group]
    group.name = 'default'
    expect(group.respond_to?(:containers)).to be(true)
    expect(group.containers.empty?).to be(true)
  end

  it 'creates attribute to hold parent id of a has_many relation' do
    container = Container.new
    expect(container.respond_to?(:container_group_id)).to be(true)
  end

  it 'gets all child entities in a has_many relation' do
    # Create a container group
    group = ContainerGroup.new(
      name: 'test_children', description: 'Testing for has_many children')
    expect(group.save).to be(true)

    # Create two containers. associate with the group.
    container1 = Container.new(container_id: 'container1', container_name: 'container1', image_id: 'image1', created: "1000")
    container1.add_to(group)
    expect(container1.save).to be(true)
    container2 = Container.new(container_id: 'container2', container_name: 'container2', image_id: 'image2', created: "2000")
    container2.add_to(group)
    expect(container2.save).to be(true)

    # Test everything is honky-dory
    containers = group.containers
    expect(containers).to be_a(Array)
    expect(containers.size).to eq(2)
    container_ids = containers.map { |s| s.id }
    expect(container_ids).to include(container1.id)
    expect(container_ids).to include(container2.id)
    @data[:group] = group
  end

  it 'gets the parent entities in belongs_to or non-dominant has_many relationthip' do
    group = @data[:group]
    containers = group.containers
    expect(containers[0].container_groups[0].id).to eql(group.id)
    expect(containers[1].container_groups[0].id).to eql(group.id)

    rule = Rule.new(name: "test_rule")
    expect(rule.save).to eq(true)

    rule_assign_def = RuleAssignDef.new(rule_id: rule.id)
    expect(rule_assign_def.save).to eq(true)

    container = containers[0]
    container_rule = ContainerRule.new
    container_rule.belongs_to(container)
    container_rule.belongs_to(rule_assign_def)
    expect(container_rule.save).to eq(true)
    expect(container_rule.container.id).to eql(container.id)
  end

  it 'handles updates to related entities when deleting' do
    group = @data[:group]
    containers = group.containers

    expect(group.delete).to be(true)
    containers = Container.get(containers[0].id, containers[1].id)
    expect(containers[0].container_group_id.empty?).to be(true)
    expect(containers[1].container_group_id.empty?).to be(true)
    expect(containers[0].container_groups.empty?).to be(true)
    expect(containers[1].container_groups.empty?).to be(true)
  end

  it 'can page results' do
    results = Container.page(limit: 1)

    expect(results.size).to be(1)
    expect(results.total).to be(2)
    expect(results.offset).to be(0)
    expect(results.limit).to be(1)

    results = Container.page

    expect(results.size).to be(2)
    expect(results.total).to be(2)
    expect(results.offset).to be(0)
    expect(results.limit).to be(SentinelDocker::Config.db.limit)
  end

  it 'will delete n items in a 1-to-n relationship when the one is deleted' do
    container = Container.new(container_id: 'container3', container_name: 'container3', image_id: 'image3', created: "3000")
    expect(container.save).to be(true)

    rule = Rule.new(name: "rule_1")
    expect(rule.save).to eq(true)

    rule_assign_def = RuleAssignDef.new(rule_id: rule.id)
    expect(rule_assign_def.save).to eq(true)

    container_rule = ContainerRule.new(container_id: container.id, rule_assign_def_id: rule_assign_def.id)
    expect(container_rule.save).to be(true)

    rule_runs = []
    (0..8).each do
      rule_runs << ContainerRuleRun.new(
        container_rule_id: container_rule.id, status: 'PASS', output: 'foobar', mode: 'check', timestamp: 'now')
      rule_runs.last.save
    end

    container_rule.delete
    rule_runs.each do |rule_run|
      expect(ContainerRuleRun.get(rule_run.id)).to eq(nil)
    end
  end

  it 'can get an array of model objects greater than 10' do
    rules = []
    12.times do |i|
      test_rule = Rule.new(name: "test_rule_#{i}")
      test_rule.save
      rules << test_rule
    end

    rules_back = Rule.get(*(rules.map {|p| p.id }))

    expect(rules_back.size).to eql(12)
  end

  after :all do
    SentinelDocker::Store.indices.delete index: 'testing'
  end
end
