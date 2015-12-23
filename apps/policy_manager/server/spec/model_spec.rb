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

include Sentinel::Models

describe Sentinel::Models do
  before :all do
    begin
      Sentinel::Store.indices.create index: 'testing'
    rescue
      puts 'Index not created. Already existed.'
    end
    Sentinel::Config.db.index_name = 'testing'
    @data = {}
  end

  it 'sets an id on save' do
    group = SystemGroup.new(
      name: 'default', description: 'This is the default group.')
    expect(group.save).to be(true)

    @data[:group_id] = group.id
    expect(group.persisted?).to be(true)
  end

  it 'find results responds to total, offset, and limit method calls' do
    results = SystemGroup.find
    expect(results.respond_to?(:total)).to be(true)
    expect(results.respond_to?('total='.to_sym)).to be(true)
    expect(results.respond_to?(:offset)).to be(true)
    expect(results.respond_to?('offset='.to_sym)).to be(true)
    expect(results.respond_to?(:limit)).to be(true)
    expect(results.respond_to?('limit='.to_sym)).to be(true)

    expect(results.total).to be(1)
    expect(results.offset).to be(nil)
    expect(results.limit).to be(Sentinel::Config.db.limit)
  end

  it 'can be obtained through a get call' do
    group = SystemGroup.get(@data[:group_id])
    @data[:group] = group
    expect(group).to be_a(SystemGroup)
    expect(group.id).to eql(@data[:group_id])
  end

  it 'can be deleted' do
    group = @data[:group]
    group.delete
    expect(SystemGroup.get(group.id)).to be(nil)
    expect(SystemGroup.find.size).to eql(0)
  end

  it 'creates method for has_many relationship' do
    expect(@data[:group].respond_to?(:systems)).to be(true)
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
    group = SystemGroup.new(description: 'foobar')
    expect(group.as_json.key?(:name)).to be(true)
  end

  it 'creates method to get all items in a has_many relation' do
    group = @data[:group]
    group.name = 'default'
    expect(group.respond_to?(:systems)).to be(true)
    expect(group.systems.empty?).to be(true)
  end

  it 'creates attribute to hold parent id of a has_many relation' do
    system = System.new
    expect(system.respond_to?(:system_group_id)).to be(true)
  end

  it 'gets all child entities in a has_many relation' do
    # Create a system group
    group = SystemGroup.new(
      name: 'test_children', description: 'Testing for has_many children')
    expect(group.save).to be(true)

    # Create two systems. associate with the group.
    system1 = System.new(hostname: 'system1', ip: '10.10.10.2')
    system1.add_to(group)
    expect(system1.save).to be(true)
    system2 = System.new(hostname: 'system2', ip: '10.10.10.3')
    system2.add_to(group)
    expect(system2.save).to be(true)

    # Test everything is honky-dory
    systems = group.systems
    expect(systems).to be_a(Array)
    expect(systems.size).to be(2)
    system_ids = systems.map { |s| s.id }
    expect(system_ids).to include(system1.id)
    expect(system_ids).to include(system2.id)
    @data[:group] = group
  end

  it 'gets the parent entities in belongs_to or non-dominant has_many relationthip' do
    group = @data[:group]
    systems = group.systems
    expect(systems[0].system_groups[0].id).to eql(group.id)
    expect(systems[1].system_groups[0].id).to eql(group.id)

    system = systems[0]
    system_policy = SystemPolicy.new(policy_id: 'fake_id')
    system_policy.belongs_to(system)
    expect(system_policy.save).to be(true)
    expect(system_policy.system.id).to eql(system.id)
  end

  it 'handles updates to related entities when deleting' do
    group = @data[:group]
    systems = group.systems

    expect(group.delete).to be(true)
    systems = System.get(systems[0].id, systems[1].id)
    expect(systems[0].system_group_id.empty?).to be(true)
    expect(systems[1].system_group_id.empty?).to be(true)
    expect(systems[0].system_groups.empty?).to be(true)
    expect(systems[1].system_groups.empty?).to be(true)
  end

  it 'can page results' do
    results = System.page(limit: 1)

    expect(results.size).to be(1)
    expect(results.total).to be(2)
    expect(results.offset).to be(0)
    expect(results.limit).to be(1)

    results = System.page

    expect(results.size).to be(2)
    expect(results.total).to be(2)
    expect(results.offset).to be(0)
    expect(results.limit).to be(Sentinel::Config.db.limit)
  end

  it 'will delete n items in a 1-to-n relationship when the one is deleted' do
    system = System.new(ip: '10.10.0.100')
    expect(system.save).to be(true)

    system_policy = SystemPolicy.new(system_id: system.id, policy_id: 'fake_id')
    expect(system_policy.save).to be(true)

    policy_runs = []
    (0..8).each do
      policy_runs << PolicyRun.new(
        system_policy_id: system_policy.id, status: 'PASS', output: 'foobar', mode: 'check', timestamp: 'now')
      policy_runs.last.save
    end

    system_policy.delete
    policy_runs.each do |policy_run|
      expect(PolicyRun.get(policy_run.id)).to be(nil)
    end
  end

  it 'can get an array of model objects greater than 10' do
    policies = []
    12.times do |i|
      test_policy = Policy.new(name: "test_policy_#{i}")
      test_policy.save
      policies << test_policy
    end

    policies_back = Policy.get(*(policies.map {|p| p.id }))

    expect(policies_back.size).to eql(12)
  end

  after :all do
    Sentinel::Store.indices.delete index: 'testing'
  end
end
