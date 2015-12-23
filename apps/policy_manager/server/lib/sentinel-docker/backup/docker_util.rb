#!/bin/ruby
# coding: utf-8
#
# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require 'sentinel-docker'
require 'sentinel-docker/models'
require 'zip'
require 'json'
require 'open3'

module SentinelDocker
  module DockerUtil

    Log = SentinelDocker::Log

    TIME_SYNC_GAP = 60*60
    SEARCH_TIME_RANGE = 60*60*3
    MAX_TRY = 2
    WAIT_SEC = 1

    RULE_SCRIPT_PATTERN = /^Comp.Linux.*/

    User = Models::User
    Container = Models::Container
    Image = Models::Image
    ImageRule = Models::ImageRule
    ContainerRule = Models::ContainerRule
    ContainerRuleRun = Models::ContainerRuleRun
    Rule = Models::Rule
    RuleAssignDef = Models::RuleAssignDef

    Config = Hashie::Mash.new(
      rule_dir: '/home/ruleadmin/newrules',
      local_es_host: 'elasticsearch',
      local_es_port: '9200',
      local_es_log_enabled: false,
      local_cache_index: 'local_cache',
      page_cache_enabled: true,
      data_cache_enabled: true,
      reports: {
        status_report: {
          cache_file:  '/opt/ibm/sentinel/tmp/status_report_cache',
          template_file: 'lib/sentinel-docker/status_report.erb'
        },
        vulnerability_report: {
          cache_file:  '/opt/ibm/sentinel/tmp/vulnerability_report_cache',
          template_file: 'lib/sentinel-docker/vulnerability_report.erb'
        }
      },
      use_stdout: true,
      check_interval: 12*60*60,  #12h
      backdate_period: 60*24*60*60,     #60days
      demo_mode: true
    )


    Local_Store = Elasticsearch::Client.new(hosts: [{ host: "#{Config.local_es_host}", port: "#{Config.local_es_port}" }], log: Config.local_es_log_enabled)

    begin
      SentinelDocker::Store.indices.create index: Config.local_cache_index
    rescue
    end

    def self.get_report(page_key, reload=false)
      raise "page_key is not specified" unless page_key
      raise "page_key must be in #{Config.reports.keys}" unless Config.reports.has_key?(page_key)
      data = nil
      config = Config.reports[page_key]
      cache_file = config.cache_file
      if Config.page_cache_enabled && !reload
        last_updated = page_updated(:pages, page_key)
        if last_updated
          path = "#{cache_file}.#{last_updated}"
          if File.exist?(path)
            data = Hashie::Mash.new(JSON.parse(File.read(path)))
          else
            data = get_data(:pages, page_key)
            if data
              updated_time = page_updated(:pages, page_key)
              if updated_time >= last_updated
                File.write("#{cache_file}.#{updated_time}", data.to_json)
                Dir::glob("#{cache_file}.*").each do |f|
                  File.delete(f) unless f.end_with?("#{updated_time}")
                end
              end
            end
          end
        end
      end

      if data && !reload
        data.page
      else
        create_report(page_key)
      end
    end

    def self.config(conf)
      Config.rule_dir=conf[:rule_dir]
    end

    def self.init_user
      user = User.find(query: { 'identity' => 'ruleadmin' }).first
      # create user if it does not exist
      unless user
        user = User.new(identity: 'ruleadmin', fullname: 'rule administarator')
        if user.save
          Log.debug "User created: #{JSON.pretty_generate(user.as_json)}"
        else
          Log.error "fail to save user"
        end
      end
      user
    end

    def self.detect_new_rules
      new_scripts = []
      Dir::glob(Config.rule_dir+"/*.py").each do |fname|
        script_path = File.basename(fname)
        next unless RULE_SCRIPT_PATTERN =~ script_path
        next unless Rule.find(query: { 'script_path' => script_path }).empty?
        new_scripts << script_path
      end
      new_scripts
    end

    def self.create_rules(new_scripts)
      new_scripts.each do |script_path|
        rule = Rule.new(name: script_path, script_path: script_path)
        if rule.save
          Log.debug "Rule created: #{JSON.pretty_generate(rule.as_json)}"
        else
          Log.error "Fail to create rule : #{JSON.pretty_generate(rule.as_json)}"
        end
      end
    end

    def self.select_rules(container_rules)
      # container_rule_ids = container_rules.map {|cr| cr.id}
      triggered_container_rules = []
      # container_rule_ids.each do |container_rule_id|
      container_rules.each do |container_rule|
        # container_rule = ContainerRule.get(container_rule_id)
        next if Config.demo_mode && !check_if_rule_in_scope(container_rule.rule.script_path)
        # next unless container_rule.rule.script_path.index('motd')
        
        #past_run = container_rule.container_rule_runs.size
        #next unless container_rule.container_rule_runs.size == 0
        next if container_rule.last_status
        triggered_container_rules << container_rule
      end
      triggered_container_rules
    end

    # def self.container(conf)
    #   conf = Hashie::Mash.new(conf)
    #   conf.delete(:id)
    #   if conf[:container_group_id]
    #     conf[:container_group_id] = Array(
    #       ContainerGroup.get(*Array(conf[:container_group_id]))
    #     ).map(&:id)
    #   end
    #   container = Container.new(conf)
    #   raise container.errors.full_messages.join(',') unless container.save
    #   container
    # end

    def self.create_image(conf)
      conf = Hashie::Mash.new(conf)
      conf.delete(:id)
      image = Image.new(conf)
      raise image.errors.full_messages.join(',') unless image.save
      image
    end

    def self.run_rules(container_rules, user=nil)

      results = []
      unless container_rules.empty?
        container_rules.each_with_index do |cr, i|
          id = run_rule(cr, user)
          next unless id
          Log.debug "  script : #{cr.rule.script_path} (#{i}/#{container_rules.size})"
          Log.debug "  num of past runs : #{cr.container_rule_runs.size}"
          Log.debug "  rule registered"
          Log.debug "    ==> request_id=#{id}, total=#{cr.container_rule_runs.size}"
          results << id
        end
      end
      results
    end

    def self.get_crawl_times(namespace, reload=false)

      raise "namespace is necessary" unless namespace

      data = (Config.data_cache_enabled && !reload) ? get_data(:crawl_times, namespace) : nil
      cached_crawl_times = data ? data.cached_crawl_times : []
      last_check = (data && data.last_check) ? Time.parse(data.last_check) : nil

      need_check = true
      if last_check && !cached_crawl_times.empty?
        if Time.now.to_i - last_check.to_i < Config.check_interval
          need_check = false
        end
      end

      end_time = Time.now
      if last_check
        begin_time = Time.at(last_check.to_i-12*60*60)
      else
        begin_time = end_time - Config.backdate_period
      end

      if need_check
        new_crawl_times = SentinelDocker::CloudsightUtil.crawl_times(namespace, begin_time, end_time) || []
      else
        new_crawl_times = []
      end

      crawl_times = (cached_crawl_times | new_crawl_times).sort!
      put_data(:crawl_times, namespace, {cached_crawl_times: crawl_times, last_check: end_time})

      crawl_times

    end



    def self.trigger_script_execution(rule_assign, crawl_time, request_id, user=nil, debug=false)

      #derive params from rule_assign
      #namespace = 'regcrawl-image-01375e8d32e4/e951019d3142'
      #script_path = 'Rule.business_use_notice.motd.py'
      #crawl_time = Time.now.strftime("%Y-%m-%dT%H:%M:%S")

      run_info = {}
      run_info[:req_id] = request_id
      run_info[:userid] = (user.identity if user) || 'ruleadmin'
      run_info[:ruledir] = "/home/#{run_info[:userid]}/newrules"
      run_info[:namespace] = rule_assign.container.namespace
      run_info[:script_path] = rule_assign.rule.script_path


      if crawl_time
        # run_info[:crawl_time] = Time.iso8601(crawl_times[0]).strftime("%Y-%m-%dT%H:%M:%S") # "2015-03-06T16:55:12"
        run_info[:crawl_time] = crawl_time
        run_info[:exec_time] = Time.now.to_i
        run_info[:cmd] = "sudo -u #{run_info[:userid]} bash -c 'cd #{run_info[:ruledir]}; /usr/bin/python #{run_info[:script_path]} #{run_info[:namespace]} #{run_info[:crawl_time]} #{run_info[:req_id]}'"
        run_info[:uncrawl_cmd] = "sudo -u #{run_info[:userid]} bash -c 'cd #{run_info[:ruledir]}; /usr/bin/python UncrawlNamespace.py #{run_info[:namespace]} #{run_info[:crawl_time]}'"
        time1 = Time.now.to_i
        _input, output, errput, thread = Open3.popen3("#{run_info[:uncrawl_cmd]}")
        run_info[:time_to_prepare_file_content] = Time.now.to_i - time1

        time2 = Time.now.to_i
        _input, output, errput, thread = Open3.popen3("#{run_info[:cmd]}")
        run_info[:time_for_script_exec] = Time.now.to_i - time2
        thread.join
        run_info[:output] = output.read
        run_info[:errput] = errput.read
        run_info[:exit_code] = thread.value.success? ? 0 : -1

        SentinelDocker::Log.debug("cmd=#{run_info[:cmd]}")
        SentinelDocker::Log.debug("exit_code=#{run_info[:exit_code]}")

      end

      run_info

    end

    def self.save_rule_run(rule_assign, run_info, user)


      es_out = run_info[:output]
      result = nil

      if run_info[:crawl_time].nil?
        result = {
          status: 'FAIL',
          output: "no crawled data available for this namespace",
          mode: 'check',
          crawl_time: 0,
          namespace: run_info[:namespace],
          timestamp: Time.now.to_i,
          user: user
        }
      elsif run_info[:exit_code] != 0
        result = {
          status: 'FAIL',
          output: "script error, #{run_info.to_json} ",
          mode: 'check',
          crawl_time: run_info[:exec_time],
          namespace: run_info[:namespace],
          timestamp: run_info[:exec_time],
          user: user
        }
      elsif es_out == nil
        result = {
          status: 'FAIL',
          output: "no result found, #{run_info.to_json} ",
          mode: 'check',
          crawl_time: run_info[:exec_time],
          namespace: run_info[:namespace],
          timestamp: run_info[:exec_time],
          user: user
        }
      elsif es_out.compliant.downcase=="unknown"
        result = {
          status: 'FAIL',
          output: "data is not available in cloudsight: #{es_out.to_json}",
          mode: 'check',
          crawl_time: Time.parse(es_out.crawled_time).to_i,
          namespace: es_out.namespace,
          timestamp: run_info[:exec_time],
          user: user
        }
      elsif es_out.execution_status.downcase != "success"
        result = {
          status: 'FAIL',
          output: "fail to execute rule script #{es_out.to_json}",
          mode: 'check',
          crawl_time: Time.parse(es_out.crawled_time).to_i,
          namespace: es_out.namespace,
          timestamp: run_info[:exec_time],
          user: user
        }
      else
        result = {
          status: es_out.compliant.downcase=="true" ? 'PASS' : 'FAIL',
          output: "#{es_out.to_json}",
          mode: 'check',
          crawl_time: Time.parse(es_out.crawled_time).to_i,
          namespace: es_out.namespace,
          timestamp: run_info[:exec_time],
          user: user
        }
      end

      rule_run_klass = rule_assign.class::RULE_RUN_CLASS
      rule_run = rule_run_klass.new(result)
      rule_run.belongs_to(rule_assign)
      rule_run.save
      rule_run

      SentinelDocker::Log.debug("run_info=#{JSON.pretty_generate(run_info)}")
      SentinelDocker::Log.debug("rule_run=#{JSON.pretty_generate(rule_run.as_json)}")

    end



    def self.check_if_rule_in_scope(script_path)

      scripts_in_scope = [
        'Comp.Linux.1-1-a.py',
        'Comp.Linux.2-1-b.py',
        # 'Comp.Linux.2-1-d.py',
        # 'Comp.Linux.3-1-a.py',
        'Comp.Linux.5-1-a.py',
        'Comp.Linux.5-1-b.py',
        'Comp.Linux.5-1-d.py',
        'Comp.Linux.5-1-e.py',
        'Comp.Linux.5-1-f.py',
        'Comp.Linux.5-1-j.py',
        'Comp.Linux.5-1-k.py',
        'Comp.Linux.5-1-l.py',
        'Comp.Linux.5-1-m.py',
        'Comp.Linux.5-1-n.py',
        'Comp.Linux.5-1-s.py',
        'Comp.Linux.6-1-d.py',
        'Comp.Linux.6-1-e.py',
        'Comp.Linux.6-1-f.py',
        'Comp.Linux.8-0-o.py'
      ]

      script_path && scripts_in_scope.include?(script_path) ? true : false

    end

    def self.run_rule(rule_assign, user=nil, debug=false)
      SentinelDocker::RuleRunner.request_new_run(rule_assign, user)
    end


    def self.assign_rule(image_id, rule_id)
      rule_assign_def = RuleAssignDef.new
      rule = Rule.get(rule_id)
      rule_assign_def.belongs_to(rule)
      rule_assign_def.save

      image_rule = ImageRule.new
      image = Image.get(image_id)
      image_rule.belongs_to(image)
      image_rule.belongs_to(rule_assign_def)
      image_rule.save

      Log.debug "Rule <#{rule.script_path}> - Image <#{image.image_id}> linked"

    end

    def self.create_container(conf)
      image = Image.find(query: { 'image_id' => conf[:image_id] }).first
      unless image
        Log.warn "no image #{conf[:image_id]} for container #{conf[:container_id]}"
        return nil
      end
      container = Container.new(conf)
      container.belongs_to(image)
      container.save
      Log.debug "Container created: #{JSON.pretty_generate(container.as_json)}"
      container
    end

    def self.put_data(type, key, data)

      result = Local_Store.update(
        index: Config.local_cache_index,
        type: type.to_s,
        id: key,
        refresh: true,
        body: { doc: {key: key, data: data}, doc_as_upsert: true }
      )
      result['_id']

    end

    def self.page_updated(type, key)

      param = {
        index: "#{Config.local_cache_index}",
        type: type.to_s,
        body: {
          query: {
            ids: { values: [key] }
          }
        },
        fields: ['data.timestamp']
      }

      response = Hashie::Mash.new(Local_Store.search(param))
      results = response.hits.hits.map do |hit|
        hit.fields
      end
      results.first ? results.first['data.timestamp'].first : 0
    end

    def self.get_data(type, key)

      param = {
        index: "#{Config.local_cache_index}",
        type: type.to_s,
        body: {
          query: {
            ids: { values: [key] }
          }
        }
      }

      response = Hashie::Mash.new(Local_Store.search(param))
      results = response.hits.hits.map do |hit|
        hit._source.data
      end
      results.first
    end

    def self.flash_data_cache
      SentinelDocker::Store.indices.delete index: Config.local_cache_index
      SentinelDocker::Store.indices.create index: Config.local_cache_index
      SentinelDocker::Store.indices.refresh
      num = 1
      exists = false
      loop do
        break if exists = SentinelDocker::Store.indices.exists(index: Config.local_cache_index) || num > 5
        sleep(2)
        num += 1
      end
      exists
    end

    def self.get_container_detail(namespace, reload=false)

      raise "namespace is necessary" unless namespace

      return nil unless md = namespace.match(/regcrawl-image-([0-9a-f]+)\/([0-9a-f]+)/)
      image_id = md[1]
      container_id = md[2]

      detail = (Config.data_cache_enabled && !reload) ? get_data(:dockerinspect, container_id) : nil

      unless detail
        details = SentinelDocker::CloudsightUtil.get_container_detail(image_id)
        details.each do |d|
          put_data(:dockerinspect, container_id, d)
          detail = d if d['dockerinspect.Id'][0...12] == container_id
        end
      end
      detail
    end

    def self.get_image_history(image_id, reload=false)
      data = Config.data_cache_enabled && !reload ? get_data(:dockerhistory, image_id) : nil
      unless data
        data = SentinelDocker::CloudsightUtil.get_image_history(image_id)
        put_data(:dockerhistory, image_id, data)
      end
      data
    end

    def self.parse_namespace(ns)

      conf = {}
      image_id = nil
      if md = ns.match(/^regcrawl-image-([0-9a-f]+)\/([0-9a-f]+)$/)
        image_id = md[1]
        container_id = md[2]
        if Container.find(query: { 'container_id' => container_id }).empty?
          detail = get_container_detail(ns)
          created = Time.iso8601(detail['dockerinspect.Created']).to_i if detail
          created ||= 0
          conf[:container_namespace] = ns
          conf[:container] = {
            container_id: container_id,
            container_name: container_id, #need to be retrieved from dockerinspect
            image_id: image_id,
            created: created #need to be retrieved from dockerinspect
          }
          Log.debug "parsed new container #{conf[:container_namespace]}"
        end
      end

      if (md = ns.match(/^regcrawl-image-([0-9a-f]+)$/)) || image_id !=nil
        image_id = md[1] if image_id == nil
        if Image.find(query: { 'image_id' => image_id }).empty?

          history = get_image_history(image_id)
          created = 0
          image_tag = nil
          if history
            created = nil
            image_tags = history['history'].first['Tags']
            image_tag = image_tags ? image_tags.first : nil
            created = history['history'].first['Created'] ||= 0
          end
          conf[:image_namespace] = "regcrawl-image-#{image_id}"
          conf[:image] = {
            image_id: image_id,
            image_name: image_tag, #need to be retrieved from dockerinspect
            created: created #need to be retrieved from dockerinspect
          }
          Log.debug "parsed new image #{conf[:image_namespace]}"
        end
      else
      end
      conf
    end

    #init_user
    #detect_new_rules
    #assign_rule
    #create_rules
    #parse_namespace
    #create_image
    #create_container

    def self.sync_server_state(begin_time, end_time)

      user=init_user

      new_scripts = detect_new_rules
      create_rules(new_scripts) unless new_scripts.empty?

      updated = false
      Log.debug "searching namespaces from #{begin_time.iso8601} to #{end_time.iso8601}"
      namespaces = SentinelDocker::CloudsightUtil.get_namespaces(begin_time, end_time)
      Log.debug "namespaces = #{namespaces}"
      new_containers = {}
      new_images = {}
      namespaces.each do |ns|
        Log.debug "analyzing namespace <#{ns}>"
        conf = parse_namespace(ns)
        if conf[:container]
          new_containers[conf[:container_namespace]] = conf[:container]
        end
        if conf[:image]
          new_images[conf[:image_namespace]] = conf[:image]
        end
      end

      updated = true unless new_images.empty? || new_containers.empty?

      Log.debug "  ==> new containers: #{JSON.pretty_generate(new_containers)}" unless new_containers.empty?
      Log.debug "  ==> new images: #{JSON.pretty_generate(new_images)}" unless new_images.empty?



      # create image
      new_images.each do |ns, conf|
        image = create_image(conf)
        new_images[ns] = image.id
        Log.debug "Image created: #{JSON.pretty_generate(image.as_json)}"
      end

      # assign rules to images (new rules are assigned to existing images)
      rule_ids = Rule.all.map {|rule| rule.id}
      Image.all.each do |image|
        ext_rule_ids = image.image_rules.map do |ir|
          ir.rule.id
        end
        image_id = image.id
        rule_ids.each do |rule_id|
          assign_rule(image_id, rule_id) unless ext_rule_ids.include?(rule_id)
        end
      end

      # assign new rules to existing containers
      Container.all.each do |container|
        container.sync_rules
      end

      # new_images.each do |ns, image_id|
      #   rule_ids.each do |rule_id|
      #     assign_rule(image_id, rule_id)
      #   end
      # end

      # create container
      new_containers.each do |ns, conf|
        new_containers[ns] = create_container(conf)
      end

      # trigger rule execution on containers

      #trigger_selected_rules(Config.demo_mode ? new_containers.values : Container.all)
      trigger_selected_rules(Container.all)

      updated

    end


    def self.trigger_selected_rules(containers)
      updated = false
      containers.each do |container|
        container_rules = select_rules(container.container_rules)
        updated = true unless container_rules.empty?
        Log.debug "container_id = #{container.container_id} trigger #{container_rules.size} out of #{container.container_rules.size} rules"
        run_rules(container_rules)
      end
      updated
    end

    def self.manual_run(containers, rules)
      Log.debug "manual run for containers=<#{containers}> and rules=<#{rules}>"
      raise 'array must be specified for containers and rules' unless containers.is_a?(Array) && rules.is_a?(Array)
      updated = false
      Container.all.each do |container|
        next unless (containers.empty? || containers.include?(container.container_id))
        container_rules = container.container_rules.select do |cr|
          rules.empty? || rules.include?(cr.rule.script_path)
        end
        updated = true unless container_rules.empty?
        Log.debug "container_id = #{container.container_id} trigger #{container_rules.size} out of #{container.container_rules.size} rules"
        run_rules(container_rules)
      end
      updated

    end


    def self.create_page(column_proc, cell_proc, page_key, template_file)
      pedigree = {}
      images = Image.all
      images.each do |image|
        docker_image_id = image.image_id[0,12]
        history = SentinelDocker::DockerUtil.get_image_history(docker_image_id)
        next unless history
        child = nil
        history['history'].each do |h|
          parent = h['Id'][0,12]
          pedigree[child] = parent if child
          child = parent
        end
      end

      system_status = {}
      # rules = Rule.all.map do |r|
      #   r.script_path
      # end
      # rules.select! do |script_path|
      #   RULE_SCRIPT_PATTERN =~ script_path && (Config.demo_mode == false || check_if_rule_in_scope(script_path))
      # end
      # rules.sort!


      image_created = {}
      image_names = {}
      cells = {}
      containers = Container.all

      containers.each do |container|

        container_status = {}

        _container_id = container.id
        docker_container_id = container.container_id
        container_status['docker_container_id'] = docker_container_id  #docker_container_id
        container_status['created'] = container.created!=0 ? Time.at(container.created).strftime("%Y-%m-%d %H:%M:%S") : ""
        image = container.image
        docker_image_id = image.image_id
        container_status['docker_image_id'] = docker_image_id
        image_created[docker_image_id] = image.created!=0 ? Time.at(image.created).strftime("%Y-%m-%d %H:%M:%S") : ""
        image_names[docker_image_id] = image.image_name || ""
        cells[docker_container_id] = cell_proc.call(container)

        image_status = system_status[container_status['docker_image_id']] || []
        image_status << container_status
        system_status[container_status['docker_image_id']] = image_status

      end

      columns = column_proc.call(cells)

      contents = File.read(template_file)
      page = Erubis::Eruby.new(contents).result(
        pedigree: pedigree,
        system_status: system_status,
        columns: columns,
        cells: cells,
        image_created: image_created,
        image_names: image_names
      )

      put_data(:pages, page_key, {page: page, timestamp:Time.now.to_i})
      page


    end

    def self.create_report(page_key)

      column_proc = nil
      cell_proc = nil

      case page_key

      when 'status_report'

        Log.debug("creating #{page_key}")

        column_proc = Proc.new do |cells|

          rules = Rule.all.map do |r|
            r.script_path
          end
          rules.select! do |script_path|
            RULE_SCRIPT_PATTERN =~ script_path && (Config.demo_mode == false || check_if_rule_in_scope(script_path))
          end
          rules.sort!
          rules
        end

        cell_proc = Proc.new do |container|
          container_rules = container.container_rules
          check_status = {}
          container_rules.each do |cr|
            rule_assign_def = cr.rule_assign_def
            rule = rule_assign_def.rule
            next unless rule
            script_path = rule.script_path
            last_run = ContainerRuleRun.find(limit: 1, query: { container_rule_id: cr.id }, sort: 'timestamp:desc')
            if last_run
              check_status[script_path] = last_run.first.as_json
            end
          end
          check_status
        end

      when 'vulnerability_report'

        Log.debug("creating #{page_key}")

        column_proc = Proc.new do |cells|
          cols = []
          summary = {}
          cells.each do |k, v|
            cols = (cols | v.keys).uniq
            v.keys.each do |key|
              summary[key] = v[key][:summary]
            end
          end
          cols.sort!
          cols.map do |col|
            [col, summary[col]]
          end
        end

        cell_proc = Proc.new do |container|
          results = SentinelDocker::CloudsightUtil.get_vulnerability_scan_results(container.namespace)
          vuls = {}
          results.each do |r|
            data = r._source
            next unless data.usnid
            next if vuls.has_key?(data.usnid)
            vuls[data.usnid] = {
              usnid: data.usnid,
              vulnerable: data.vulnerable,
              timestamp: data.timestamp,
              summary: data.summary,
              url: "http://elastic2-cs.sl.cloud9.ibm.com:9200/#{r._index}/#{r._type}/#{r._id}/_source"
            }
          end
          vuls
        end

      else
        raise "invalid page_key :#{page_key}"
      end

      create_page(column_proc, cell_proc, page_key, Config.reports[page_key].template_file)

    end

    def self.create_status_report_old

      pedigree = {}
      images = Image.all
      images.each do |image|
        docker_image_id = image.image_id[0,12]
        history = SentinelDocker::DockerUtil.get_image_history(docker_image_id)

        child = nil
        history['history'].each do |h|
          parent = h['Id'][0,12]
          pedigree[child] = parent if child
          child = parent
        end
      end

      system_status = {}

      rules = Rule.all.map do |r|
        r.script_path
      end
      rules.select! do |script_path|
        RULE_SCRIPT_PATTERN =~ script_path
      end
      rules.sort!

      system_status['rules'] = rules

      image_created = {}

      containers = Container.all

      containers.each do |container|

        container_status = {}

        _container_id = container.id
        container_status['docker_container_id'] = container.container_id  #docker_container_id
        container_status['created'] = container.created!=0 ? Time.at(container.created).strftime("%Y-%m-%d %H:%M:%S") : ""
        image = container.image
        docker_image_id = image.image_id
        container_status['docker_image_id'] = docker_image_id
        image_created[docker_image_id] = image.created!=0 ? Time.at(image.created).strftime("%Y-%m-%d %H:%M:%S") : ""

        container_rules = container.container_rules
        check_status = {}
        container_rules.each do |cr|
          rule = cr.rule_assign_def.rule
          script_path = rule.script_path
          rule_runs = cr.container_rule_runs
          unless rule_runs.empty?
            rr = rule_runs.first
            check_status[script_path] = rr.as_json
          end

        end
        container_status['check_status'] = check_status

        image_status = system_status[container_status['docker_image_id']] || []
        image_status << container_status
        system_status[container_status['docker_image_id']] = image_status

      end

      erb = ERB.new(File.read('lib/sentinel-docker/report.erb'))
      page = erb.result(binding)

      put_data(:pages, 'status_report', {page: page, timestamp:Time.now.to_i})
      page

    end

  end

end
