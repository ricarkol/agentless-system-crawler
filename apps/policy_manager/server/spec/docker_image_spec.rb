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
    # @container_images = {}
    # @rule_scripts = {}
    @container_images = {
      # "3603892f9519"=>"61afc26cd88e96f8903d11170c61f4004697e46bc7a3f94ef60ec92114c75e85" ,
      # "cc1a225fc739"=>"68ed05e1d9b7cd7429b24eeaac3405d03caa696f4e18259f820505c2aca0f28e" ,
      # "9b8e277ffacb"=>"868be653dea3ff6082b043c0f34b95bb180cc82ab14a18d9d6b8e27b7929762c" ,
      # "e46ebf4351bc"=>"868be653dea3ff6082b043c0f34b95bb180cc82ab14a18d9d6b8e27b7929762c" ,
      # "99b272958373"=>"ecc04d6d638cc9473d1ac0061f1e8575da6e4b6978004a1cfde23ac35862a03b" ,
      "0fcd5456aa35"=>"01375e8d32e457893028dee10093c1c4335116b4c05e3600e6561c17c2ce0f67" ,
      "493461cc7474"=>"0beee7f478c860c8444aa6a3966e1cb0cd574a01c874fc5dcc48585bd45dba52" ,
      "f9927a2a821e"=>"2cea2911ebcb7f1bb6fb3cadcc8805aaa9df07fba84e7f7f8f5dac0744dada60"
    }

    @rule_scripts = [
      'Rule.authentication.pass_max_days.py',
      'Rule.authentication.pass_min_len.py',
      'Rule.authentication.pass_min_days.py',
      'Rule.authentication.remember_parameter_of_pam_unix_so.py',
      'Rule.service_integrity.systematic_logon_attacks.py',
      'Rule.business_use_notice.motd.py'
    ]

  end

  # @container_images = {
  #   "container1" => "image1",
  #   "container2" => "image2"
  # }


  it 'creates image' do

    @container_images.values.uniq.each_with_index do |image_id, i|
      image = Image.new(image_id: image_id, image_name: "image#{i}", created: Time.now.to_i, created_by: "ls -al", created_from: "image0")
      expect(image.save).to eq(true)
    end

  end

  it 'assigns rule to image' do

    images = Image.all
    expect(images).to be_a(Array)
    image_map = {}
    images.each do |image|
      expect(image.image_id).not_to be_nil
      expect(@container_images.values.include?(image.image_id)).to eq(true)
      image_map[image.image_id] = image
    end

    rule_map = {}

    @rule_scripts.each do |script|
      rule = Rule.new(name: script, script_path: script)
      expect(rule.save).to eq(true)
      expect(rule.id).not_to be_nil
      rule_map[script] = rule
    end

    @container_images.values.uniq.each_with_index do |image_id, i|

      image = image_map[image_id]

      @rule_scripts.each do |script|


        rule = rule_map[script]

        rule_assign_def = RuleAssignDef.new
        rule_assign_def.belongs_to(rule)
        expect(rule_assign_def.save).to eq(true)
        expect(rule_assign_def.id).not_to be_nil

        image_rule = ImageRule.new
        image_rule.belongs_to(image)
        image_rule.belongs_to(rule_assign_def)
        expect(image_rule.save).to eq(true)
        expect(image_rule.id).not_to be_nil
        expect(image.image_rules.map {|ir| ir.image_id}.include?(image.id)).to eq(true)
        expect(image.image_rules.map {|ir| ir.rule_assign_def_id}.include?(rule_assign_def.id)).to eq(true)

      end

    end

  end

  it 'gets image_rule' do
    images = Image.all
    expect(images).to be_a(Array)
    images.each do |image|
      expect(image.image_rules).to be_a(Array)
      expect(image.image_rules.size).to eq(@rule_scripts.size)
    end
  end

  it 'create new container from image and see container_rule' do

    images = Image.all
    expect(images).to be_a(Array)
    image_map = {}
    images.each do |image|
      image_map[image.image_id] = image
    end

    @container_images.each_with_index do |(container_id, image_id), i|
      image = image_map[image_id]
      expect(image.containers).to be_a(Array)
      num = image.containers.size
      container = Container.new(container_id: container_id, container_name: "container#{i}", image_id: image.id, created: "1000")
      container.belongs_to(image)
      expect(container.save).to eq(true)
      expect(container.image.id).to eq(image.id)
      expect(container.image.image_id).to eq(image_id)
      expect(container.container_rules).to be_a(Array)
      expect(container.container_rules.size).to eq(@rule_scripts.size)
      expect(image.containers.size).to eq(num+1)
    end

  end

  it 'runs a rule on an container and see rule_runs' do

    user = User.new(identity: 'ruleadmin', fullname: 'rule administarator')
    expect(user.save).to eq(true)
    expect(user.id).not_to be_nil

    containers = Container.all
    expect(containers).to be_a(Array)

    containers.each do |container|

      puts "----------------------------"      
      puts "container_id = #{container.container_id}"
      expect(container.container_rules.size).to eq(@rule_scripts.size)
      puts "num of container_rules = #{container.container_rules.size}"
      container_rule_ids = container.container_rules.map {|cr| cr.id}

      container_rule_ids.each do |container_rule_id|
        container_rule = ContainerRule.get(container_rule_id)
        puts "  container_rule = #{container_rule.id}"
        puts "    script = #{container_rule.rule.script_path}"
        expect(container_rule.container_rule_runs).to be_a(Array)
        puts "    num of container_rule_runs : #{container_rule.container_rule_runs.size}"
        puts container_rule.container_rule_runs.to_json unless container_rule.container_rule_runs.empty?
        expect(container_rule.container_rule_runs.empty?).to eq(true)
        rule_run = SentinelDocker::DockerUtil.run_rule(container_rule)
        puts "    execute rule"
        puts "    ==> rule_run=#{rule_run.as_json}, total=#{container_rule.container_rule_runs.size}"
        expect(container_rule.container_rule_runs).to be_a(Array)
        expect(container_rule.container_rule_runs.size).to eq(1)
        rule_run = SentinelDocker::DockerUtil.run_rule(container_rule)
        puts "    execute rule"
        puts "    ==> rule_run=#{rule_run.as_json}, total=#{container_rule.container_rule_runs.size}"
        expect(container_rule.container_rule_runs).to be_a(Array)
        expect(container_rule.container_rule_runs.size).to eq(2)
      end

    end

  end

  # it 'update rule assign def' do

  # end

  # it 'delete rule assign def' do

  # end

  # it '' do

  # end

  # it 'assign rule to image (override)' do

  # end

  # it 'assign rule to container (override)' do

  # end

  # it 'assign rule to container (override)' do

  # end

  # it 'update rule and increase its version' do

  # end

  # it 'each rule_run includes correct rule id and its version' do

  # end

  after :all do
    SentinelDocker::Store.indices.delete index: 'testing'
  end

end
