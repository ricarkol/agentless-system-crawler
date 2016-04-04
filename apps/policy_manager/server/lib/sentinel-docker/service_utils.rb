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
#require 'sentinel-docker/models'
require 'zip'
require 'json'
require 'open3'

module SentinelDocker
  module ServiceUtils
    include SentinelDocker::Models

    Log = SentinelDocker::Log
    CloudsightReader = SentinelDocker::CloudsightReader

    def self.get_rules(namespace, owner_namespace)
      #resolve tenant and group from namespace
      #how to resolve ns
      tenant_id = nil
      t = Tenant.find(query: { 'tenant.owner_namespaces' => owner_namespace }).first
      fail 'no matechd tenant found' unless t

      image = t.image(namespace)
      g = nil
      if image
        g = image.group
      else
        g = tenant.default_group

        created_time = Time.now.to_i
        image = Image.new(
          name: namespace,
          namespace: namespace,
          owner_namespace: owner_namespace,
          created: Time.now.to_i,
          assigned: Time.now.to_i
        )
        image.group_id = g.id
        image.tenant_id = t.id
        fail "fail to save image : #{image.errors.full_messages.join(',')}" unless image.save

        Log.debug("new image <#{image.id}> for #{namespace} has been created")
      end

      result = {}
      g.rules.each do |r|
        result[r.name] = {id: r.id, timestamp: r.timestamp}
      end
      result
    end

    def self.get_rules_per_tenant(tenant)
      fail 'no tenant specified' unless tenant
      tenant.groups.map do |g|
        {group: g.name, value: g.rules.map{|r| r.name}}
      end
    end

    def self.get_image_status_per_tenant(tenant)

      fail 'no tenant specified' unless tenant

      #namespaces = CloudsightReader.get_namespaces
      ct = CloudsightReader.get_crawl_times_by_owner(tenant.owner_namespaces)
      rs = CloudsightReader.get_results_by_owner(tenant.owner_namespaces)

      # res = namespaces[namespace]
      results = tenant.images.map do |image|

        # this is heavy
        g = image.group

        namespace = image.namespace

        if ct.has_key?(namespace)

          crawl_times = ct[namespace]
          
          first_crawl = crawl_times.first
          latest_crawl = crawl_times.last
        
        else
          puts "namespace #{namespace} is not found in owner_namespaces #{tenant.owner_namespaces}"

          crawl_times = CloudsightReader.get_crawl_times(image)
          first_crawl = crawl_times.first
          latest_crawl = crawl_times.last

        end

        if (rs.has_key? namespace) && (rs[namespace][:crawl_time] == latest_crawl)
          result = rs[namespace]
          puts "result=#{result}"
        else
          # this is heavy
          result = CloudsightReader.get_result(image, latest_crawl)
          puts "result2=#{result}"
        end


        result = {
          namespace: namespace,
          group: g ? g.name : 'no_group',
          first_crawl: first_crawl,
          latest_crawl: latest_crawl,
          latest_vul_result: result[:vulnerability],
          latest_comp_result: result[:compliance][:overall],
          auto_assigned: true,
          assigned_time: image ? Time.at(image.assigned).iso8601 : nil
        }

        result

      end

      results

    end

    def self.get_groups(tenant)

      fail 'no tenant specified' unless tenant
      tenant.groups.map do |g|
        {name: g.name, id: g.id, default: g.default}
      end

    end


    def self.get_tenant_rules(tenant, group_id)

      fail 'no tenant specified' unless tenant
      rules = nil
      if group_id
        group = tenant.group_by_id(group_id)
        fail 'no group found' unless group
        rules = group.rules
      else
        rules = tenant.rules || []
      end
      rules.map do |r|
        r.as_json(only: [:id, :name, :script_path, :description, :long_description, :platforms, :rule_group_name, :timestamp])
      end
    end

    def self.get_auto_assign(tenant, group_id)
      fail 'no tenant specified' unless tenant
      fail 'no group specified' unless group_id
      group = tenant.group_by_id(group_id)
      fail 'no group found' unless group
      group.auto_assign ? JSON.parse(group.auto_assign) : nil
    end

    def self.set_auto_assign(tenant, group_id, conf)

      fail 'no tenant specified' unless tenant
      fail 'no group specified' unless group_id
      fail "array of auto assign rules must be specified in body" unless conf.kind_of?(Array)

      group = tenant.group_by_id(group_id)
      fail 'no group found' unless group
      group.auto_assign = conf.to_json
      fail 'fail to update group' unless group.save
      group
    end

    def self.set_namespaces_to_group(tenant, group_id, conf, is_admin=false)

      fail 'no tenant specified' unless tenant
      fail 'no group specified' unless group_id
      group = tenant.group_by_id(group_id)
      fail 'no group found' unless group

      images = []

      begin
        arr = conf
        arr.each do |namespace|
          if is_admin
            image = Image.find(query: { 'namespace' => namespace }).first
            image.tenant_id = tenant.id unless image.tenant.id == tenant.id 
            image.group_id = nil
            fail "fail to change tenant which belongs to image" unless image.save
          else
            image = tenant.image(namespace)
          end
          fail "invalid namespace : #{namespace}" unless image
          images << image
        end
      rescue JSON::ParserError
        fail "json array of namespaces must be in body"
      end

      images.each do |image|
        image.group_id = group.id
        image.assigned = Time.now.to_i
        image.save
      end

    end

    def self.set_tenant_rules(tenant, group_id, conf, default=false)

      fail 'no tenant specified' unless tenant
      fail 'no group specified' unless group_id
      group = tenant.group_by_id(group_id)
      fail 'no group found' unless group

      rule_ids = []
      all_rule_ids = tenant.rules.map {|r| r.id}
      begin
        conf.each do |rule_id|
          fail "invalid rule : #{rule_id}" unless all_rule_ids.include? rule_id
          rule_ids << rule_id
        end
      rescue JSON::ParserError
        fail "array of rule ids must be in body"
      end

      group.rule_id = rule_ids

      if default && !group.default
        default_group = tenant.default_group
        default_group.default = false
        fail default_group.errors.full_messages.join(',') unless default_group.save

        group.default = true
        Log.debug("default group is changed from #{default_group.name} to #{group.name}")
      end

      fail group.errors.full_messages.join(',') unless group.save

      ''
    end

    #############################

    # def self.get_vulnerability_counts(tenant, namespace)

    #   check_namespace(tenant, namespace)

    #   crawl_times = CloudsightReader.get_crawl_times(namespace)

    #   fail_array = []
    #   pass_array = []

    #   crawl_times.sort!

    #   crawl_times.each do |timestamp|

    #     result = CloudsightReader.get_result(namespace, timestamp)
    #     vul_false_count = result[:vulnerability][:false_count] || 0
    #     vul_total_count = result[:vulnerability][:total_count] || 0

    #     #timestr = Time.iso8601(timestamp.sub(/(\d)00$/,'\1:00')).strftime("%Y-%m-%d %H:%M:%S")
    #     timestr = timestamp.sub(/^(\d\d\d\d-\d\d-\d\d)T(\d\d:\d\d:\d\d)[+-]\d\d\d\d$/,'\1 \2')
    #     fail_array << [timestr, vul_total_count-vul_false_count]
    #     pass_array << [timestr, vul_false_count]

    #   end

    #   [fail_array, pass_array]

    # end


    def self.get_vulnerability_page(tenant, namespace, timestamp)

      image = check_namespace(tenant, namespace)

      crawl_times = CloudsightReader.get_crawl_times(image)

      fail "no crawl data for <#{namespace}> is found" unless timestamp && (crawl_times.include? timestamp)

      vul_results = CloudsightReader.get_vulnerability_results(image, timestamp)

      result = CloudsightReader.get_result(image, timestamp)

      # vul_false_count = vul_results.values.select { |r| r.vulnerable == false }.size
      # vul_total_count = vul_results.size
      # usn_ids = vul_results.keys.sort
      # vul_table = {}

      # vulnerability = usn_ids.map do |usnid|
      #   vul = vul_results[usnid]
      #   {
      #     usnid: usnid,
      #     check: vul.vulnerable ? 'Vulnerable' : 'Safe',
      #     description: vul.summary
      #   }
      # end

      result = {
        namespace: namespace,
        crawl_time: timestamp,
        overall: result[:vulnerability],
        vulnerability: vul_results
      }

    end

    def self.get_result_page_per_namespace(tenant, namespace)

      image = check_namespace(tenant, namespace)

      # namespaces = CloudsightReader.get_namespaces

      crawl_times = CloudsightReader.get_crawl_times(image)

      lines = {}

      crawl_times.each do |crawl_time|
        lines[crawl_time] = get_result_row(tenant, image, crawl_time)
      end

      lines

    end

    def self.get_result_page(tenant)

      fail 'no tenant specified' unless tenant

      lines = {}
      tenant.images.each do |image|
        #image.namespace

        crawl_times = CloudsightReader.get_crawl_times(image)
        crawl_time = crawl_times.last

        if crawl_time && image.namespace
          lines[image.namespace] = get_result_row(tenant, image, crawl_time)
        end
      end
      lines

    end

    # def self.get_result_page(tenant, timestamp)

    #   fail 'no tenant specified' unless tenant

    #   lines = {}
    #   tenant.images.each do |image|
    #     crawl_times = CloudsightReader.get_crawl_times(image.namespace)

    #     crawl_time = nil
    #     crawl_times.each do |t|
    #       break if t > timestamp
    #       crawl_time = t
    #     end

    #     if crawl_time
    #       lines[namespace] = get_result_row(tenant, image, crawl_time)
    #     end
    #   end
    #   lines

    # end

    def self.get_crawl_times(tenant, namespace)
      image = check_namespace(tenant, namespace)
      CloudsightReader.get_crawl_times(image)
    end

    def self.get_result(tenant, namespace, timestamp)
      image = check_namespace(tenant, namespace)
      CloudsightReader.get_result(image, timestamp)
    end

    def self.get_namespaces(tenant)
      tenant.images.map {|img| img.namespace}
    end

    def self.get_rule_descriptions(tenant)

      rule_descriptions = {}

      rule_descriptions['Linux.1-1-a'] = <<-EOS
      <font face="Verdana">Each UID must only be used once</font>
      EOS

      rule_descriptions['Linux.2-1-c'] = <<-EOS
      <font face="Verdana">One of these two options must be implemented:</font>
      <ul>
      <li type="disc">
      <font face="Verdana">Parameters of "retry=3 minlen=8 dcredit=-1 ucredit=0 lcredit=-1 ocredit=0 type= reject_username" in /etc/pam.d/system-auth to the "password required pam_cracklib.so ..." stanza</font>
      </li>
      <li type="disc">
      <font face="Verdana">parameters of "min=disabled,8,8,8,8 passphrase=0 random=0 enforce=everyone" in /etc/pam.d/system-auth to the "password required pam_passwdqc.so" stanza</font>
      </li>
      </ul>
      <font face="Verdana">
      <br>
      Note: The "type=" parameter to pam_crackllib.so may be omitted if it causes problems.
        <br>
      Note: Use of full path and/or $ISA to pam modules is optional.
        </font>
      EOS

      rule_descriptions['Linux.2-1-d'] = <<-EOS
      <font face="Verdana" color="#0000FF">/etc/login.defs must include this line:</font>
      <br>
      <font face="Verdana">PASS_MIN_DAYS 1</font>
      <br>
      <br>
      <font face="Verdana">Field 4 of /etc/shadow must be 1 for all userids with a password assigned.</font>',
      EOS
      
      rule_descriptions['Linux.2-1-e'] = <<-EOS
        <font face="Verdana">RedHat Enterprise Linux/RedHat Application Server (any version):</font>
        <br>
        <br>
        <b>
        <font face="Verdana">password $CONTROL pam_unix.so remember=7 use_authtok md5 shadow</font>
        </b>
        <br>
        <ul>
        <li type="disc">
        <font face="Verdana">This statement must appear in /etc/pam.d/system-auth</font>
        </li>
        </ul>
        <br>
        <font face="Verdana">Note: $CONTROL in the following examples must be one of "required", or "sufficient".</font>
        <br>
        <font face="Verdana">Note: Use of full path and/or $ISA to pam modules is optional. </font>
        <br>
        <font face="Verdana">Note: It is acceptable to replace "md5" with "sha512" in the settings above.</font>
        <br>
        <font face="Verdana">Note: For Red Hat Enterprise Linux V6 and later: </font>
        <font face="Verdana" color="#0000FF">T</font>
        <font face="Verdana">his control must ADDITIONALLY be applied to the /etc/pam.d/password-auth file.</font>', 
        EOS

      rule_descriptions['Linux.2-1-b'] = <<-EOS
      <font face="Verdana" color="#0000FF">/etc/login.defs must include this line:</font>
      <br>
      <font face="Verdana">PASS_MAX_DAYS 90</font>
      <font face="Verdana">Field 5 of /etc/shadow must be "90"</font>
      <br>------------------------<br>
      <font face="Verdana">Note: This setting in /etc/shadow is not required on userids without a password, <br>
      nor is it required on userids that meet the requirements in "</font>
        <b>
        <font face="Verdana">Exemptions to password rules</font>
        </b>
        <font face="Verdana">"</font>'
      EOS

      rule_descriptions

    end

    private 

    def self.check_namespace(tenant, namespace)
      fail 'no tenant specified' unless tenant
      fail 'namespace must be specified' unless namespace
      image = tenant.image(namespace)
      fail 'no image for this namespace found' unless image
      image
    end

    def self.get_result_row(tenant, image, crawl_time)
      fail 'no tenant specified' unless tenant
      fail 'no image specified' unless image

      result = CloudsightReader.get_result(image, crawl_time)

      md = image.namespace.match(/^(\S+)\/(\S+)\/(\S+)\:(\S+)$/)

      row_data = {
        owner_namespace: image.owner_namespace,
        namespace: image.namespace,
        registry: md ? md[1] : nil,
        image_name: md ? md[3] : nil,
        tag: md ? md[4] : nil,
        crawl_time: crawl_time,
        vulnerability: result[:vulnerability],
        compliance: result && result[:compliance] ? result[:compliance][:overall] : nil,
        results: result && result[:compliance] ? result[:compliance][:summary] : nil
      }


    # def self.get_result_row(tenant, image, crawl_time)
    #   result = CloudsightReader.get_result(image.namespace, crawl_time)
    #   row_data = nil

    #   if result
    #     row_data = {
    #       tenant: image.owner_namespace,
    #       namespace: image.namespace,
    #       crawl_time: crawl_time,
    #       vulnerability: result[:vulnerability][:overall],
    #       compliance: result[:compliance][:overall],
    #       results: result[:compliance][:summary]
    #     }
    #   end

      row_data

    end


  end

end

