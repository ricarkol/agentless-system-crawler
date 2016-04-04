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
# require 'sentinel-docker/docker_util'
# require 'sentinel-docker/rule_runner'
# require 'sentinel-docker/scserver_control'

include SentinelDocker::Models


CloudsightReader = SentinelDocker::CloudsightReader
Util = SentinelDocker::Util

DescriptionDict = {
  "Linux.1-1-a" => "UID must be used only once",
  "Linux.2-1-b" => "Maximum password age",
  "Linux.2-1-c" => "minimum password length",
  "Linux.2-1-d" => "minimum days before password change",
  "Linux.2-1-e" => "prevent password reuse",
  "Linux.3-1-a" => "motd file checking",
  "Linux.3-2-b" => "UMASK value 077 in /etc/login.defs",
  "Linux.3-2-e" => "/etc/profile",
  "Linux.3-2-f" => "/etc/csh.login",
  "Linux.5-1-a" => "Read/write access of ~root/.rhosts only by root",
  "Linux.5-1-b" => "Read/write access of ~root/.netrc only by root",
  "Linux.5-1-d" => "permission check of /usr",
  "Linux.5-1-e" => "permission check of /etc",
  "Linux.5-1-f" => "permission check of /etc/security/opasswd",
  "Linux.5-1-g" => "permission check of /etc/shadow",
  "Linux.5-1-h" => "permission check of /etc/profile.d/IBMsinit.sh",
  "Linux.5-1-i" => "permission check of /etc/profile.d/IBMsinit.sh",
  "Linux.5-1-j" => "permission check of /var",
  "Linux.5-1-k" => "permission check of /var/tmp",
  "Linux.5-1-l" => "permission check of /var/log",
  "Linux.5-1-m" => "permission check of /var/log/faillog",
  "Linux.5-1-n" => "permission check of /var/log/tallylog",
  "Linux.5-1-o" => "permission check of /var/log/syslog or /var/log/messages",
  "Linux.5-1-p" => "permission check of /var/log/wtmp",
  "Linux.5-1-q" => "permission check of /var/log/auth.log or /var/log/secure",
  "Linux.5-1-r" => "permission check of /tmp",
  "Linux.5-1-s" => "permission check of snmpd.conf",
  "Linux.5-2-c" => "enforce default no access policy",
  "Linux.5-2-d" => "ftp access restriction",
  "Linux.6-1-a" => "syslog file checking",
  "Linux.6-1-b" => "messages file checking",
  "Linux.6-1-c" => "syslog file checking",
  "Linux.6-1-d" => "wtmp file checking",
  "Linux.6-1-e" => "faillog file checking",
  "Linux.6-1-f" => "tallylog file checking",
  "Linux.6-1-g" => "secure or auth file checking",
  "Linux.8-0-o" => "no_hosts_equiv must be present",
  "Linux.8-0-u" => "net.ipv4.tcp_syncookies =1",
  "Linux.8-0-v" => "net.ipv4.icmp_echo_ignore_broadcasts = 1",
  "Linux.8-0-w" => "net.ipv4.conf.all.accept_redirects = 0",
}

ScriptDict = {
  "Linux.1-1-a" => "Comp.Linux.1-1-a.py",
  "Linux.2-1-b" => "Comp.Linux.2-1-b.py",
  "Linux.2-1-c" => "Comp.Linux.2-1-c.py",
  "Linux.2-1-d" => "Comp.Linux.2-1-d.py",
  "Linux.2-1-e" => "Comp.Linux.2-1-e.py",
  "Linux.3-1-a" => "Comp.Linux.3-1-a.py",
  "Linux.3-2-b" => "Comp.Linux.3-2-b.py",
  "Linux.3-2-e" => "Comp.Linux.3-2-e.py",
  "Linux.3-2-f" => "Comp.Linux.3-2-f.py",
  "Linux.5-1-a" => "Comp.Linux.5-1-a.py",
  "Linux.5-1-b" => "Comp.Linux.5-1-b.py",
  "Linux.5-1-d" => "Comp.Linux.5-1-d.py",
  "Linux.5-1-e" => "Comp.Linux.5-1-e.py",
  "Linux.5-1-f" => "Comp.Linux.5-1-f.py",
  "Linux.5-1-g" => "Comp.Linux.5-1-g.py",
  "Linux.5-1-h" => "Comp.Linux.5-1-h.py",
  "Linux.5-1-i" => "Comp.Linux.5-1-i.py",
  "Linux.5-1-j" => "Comp.Linux.5-1-j.py",
  "Linux.5-1-k" => "Comp.Linux.5-1-k.py",
  "Linux.5-1-l" => "Comp.Linux.5-1-l.py",
  "Linux.5-1-m" => "Comp.Linux.5-1-m.py",
  "Linux.5-1-n" => "Comp.Linux.5-1-n.py",
  "Linux.5-1-o" => "Comp.Linux.5-1-o.py",
  "Linux.5-1-p" => "Comp.Linux.5-1-p.py",
  "Linux.5-1-q" => "Comp.Linux.5-1-q.py",
  "Linux.5-1-r" => "Comp.Linux.5-1-r.py",
  "Linux.5-1-s" => "Comp.Linux.5-1-s.py",
  "Linux.5-2-c" => "Comp.Linux.5-2-c.py",
  "Linux.5-2-d" => "Comp.Linux.5-2-d.py",
  "Linux.6-1-a" => "Comp.Linux.6-1-a.py",
  "Linux.6-1-b" => "Comp.Linux.6-1-b.py",
  "Linux.6-1-c" => "Comp.Linux.6-1-c.py",
  "Linux.6-1-d" => "Comp.Linux.6-1-d.py",
  "Linux.6-1-e" => "Comp.Linux.6-1-e.py",
  "Linux.6-1-f" => "Comp.Linux.6-1-f.py",
  "Linux.6-1-g" => "Comp.Linux.6-1-g.py",
  "Linux.8-0-o" => "Comp.Linux.8-0-o.py",
  "Linux.8-0-u" => "Comp.Linux.8-0-u.py",
  "Linux.8-0-v" => "Comp.Linux.8-0-v.py",
  "Linux.8-0-w" => "Comp.Linux.8-0-w.py"
}

# /home/sentinel/rulezips
#     /default/*.zip
#     /tenant1/default/*.zip
#     /tenant1/group1/*.zip
#     /tenant2/default/*.zip
#     /tenant2/group2/*.zip
#create tenant 
#create 

#create tenant (create default group)
#rename default group to "dev"
#create group "test"
#create group "prod"

Demo_Data = [
#  {tenant: 'CITI', owner_namespaces: %w[citi_ns], group: %w[DEV TEST PROD], users:%w[citi_admin]},
#  {tenant: 'ADP', owner_namespaces: %w[adp_ns], group: %w[DEV TEST PROD], users:%w[adp_admin]},
#  {tenant: 'Toyota', owner_namespaces: %w[toyota_ns], group: %w[DEV TEST PROD], users:%w[toyota_admin]},
 {tenant: 'CITI', owner_namespaces: %w[alagala alchemybuild alexrub amywan arpanroy bigbrother breadbox carmand cbr74img cfsworkload], group: %w[DEV], patterns:[{left: 'namespace', pattern: '10\.114\.222.*'},{left: 'owner_namespace', pattern: '^rkoller\.*'}], users:%w[citi_admin]},
 {tenant: 'ADP', owner_namespaces: %w[f3docker faxg gbcont gradsx ibm_containers_111 icetest5 img_rd1 ishizumi jastx jejtest jgarcows junge_materna], group: %w[PROD], patterns:[{left: 'namespace', pattern: '.*lahori.*'},{left: 'owner_namespace', pattern: '^kollerr*'}], users:%w[adp_admin]},
 {tenant: 'Toyota', owner_namespaces: %w[lahori library mamacdon mdsserver mfpdocker miles molepigeon morten_ie_ibm_com mraj msamano nihillno nikh], group: %w[DEV PROD], patterns:[{left: 'owner_namespace', pattern: '^btak*'},{left: 'namespace', pattern: '.*lahori.*'}], users:%w[toyota_admin]},
 {tenant: 'IBM', owner_namespaces: %w[niklas priyareg ptuton ra01 rahulnarain ram_ns riccic rich ryanjbaxter snible2 tankcdr testapp01 vdowling_ecosystem zubcevic], group: %w[UNKNOWN], users:%w[ibm_admin]}
]

DEFAULT_RULE_ZIP_DIR= '/home/sentinel/rulezips/default'

# set up demo data

def assigned_group(res, tenant)
  
  group = nil
  tenant.groups.each do |g|
    
    next unless g.auto_assign
    auto_assign = JSON.parse(g.auto_assign)

    group_found = false
    auto_assign.each do |aar|
      left_value = res[aar['left']]
      pattern = "/#{aar['pattern']}/"
      # puts "left_value=#{left_value}"
      # puts "pattern=#{pattern}"
      if left_value && left_value.match(pattern)
        group_found = true
        break
      end
    end
    # puts "hit=#{hit}"
    if group_found
      group = g
      break
    end

  end

  group

end


Demo_Data.each do |data|


  tenant = Tenant.new(name: data[:tenant], owner_namespaces: data[:owner_namespaces])
  fail tenant.errors.full_messages.join(',') unless tenant.save
  puts "create tenant #{data[:tenant]}"
  print "load rule "

  rule_ids = []
  Dir::glob(File.join(DEFAULT_RULE_ZIP_DIR, "*.zip")).each do |f|
    metadata = Util.load_metadata(f)
    rule = Util.set_rule(tenant, metadata, f)
    rule_ids << rule.id
    print "#{rule.name} "
  end
  puts ''
  puts "load rule completed"

  data[:group].each_with_index do |group_name, j|
    group = Group.new(name: group_name)
    group.tenant_id = tenant.id
    group.default = true if j == 0
    group.auto_assign = data[:patterns].to_json if (j == data[:group].size-1) && data[:patterns]
    group.rule_id = rule_ids
    fail group.errors.full_messages.join(',') unless group.save
    puts "create group #{group.name}"
  end

  data[:users].each do |u|
    user = User.new(identity: u)
    user.tenant_id = tenant.id
    fail user.errors.full_messages.join(',') unless user.save    
    puts "create user #{u}"
  end

end

owner_namespace_map = {}
Tenant.all.each do |t|
  on = t.owner_namespaces || []
  next if on.empty?
  on.each do |ns|
    owner_namespace_map[ns] = t
  end
end

default_tenant = Tenant.find(query: { 'name' => 'IBM' }).first

registered_namespaces = Image.all.map { |image| image.namespace }


# load images

CloudsightReader.init
CloudsightReader.update_namespaces
namespaces = CloudsightReader.get_namespaces # this is used only from here


namespaces.each do |namespace, res|

  puts "--------------- #{namespace} -----------------"

  next if registered_namespaces.include? namespace

  # find tenant from owner_namespace
  owner_namespace = res[:owner_namespace]
  




  if t = owner_namespace_map[owner_namespace]
    tenant_found = true
    groups = t.groups
  else
    tenant_found = false
    t = default_tenant
    groups = []
  end
  

  tenant_id = t.id

  puts "owner_namespace=#{owner_namespace}, tenant=#{t.name} #{tenant_found ? '' : '(default)'}"

  # find group matched with pattern
  group = assigned_group(res, t) if tenant_found

  # set default group unless matched
  group_id = group ? group.id : t.default_group.id

  first_crawl = res[:image][res[:crawl_times].first]

  created_time = Time.now.to_i

  image = Image.new(
    name: namespace, 
    namespace: namespace, 
    owner_namespace: first_crawl[:owner_namespace],
    system_type: first_crawl[:system_type],
    first_crawled: res[:crawl_times].first,
    created: created_time,
    assigned: created_time
    )
  image.group_id = group_id
  image.tenant_id = tenant_id
  fail "fail to save image : #{image.errors.full_messages.join(',')}" unless image.save

  puts "image (#{namespace}) is created in group=#{group ? group.name : t.default_group.name+' (default)'}"

  crawl_times = res[:crawl_times] || []
  crawl_times.each do |crawl_time|
    puts "loading result at crawl_time=#{crawl_time}"
    snapshot = CloudsightReader.get_result(image, crawl_time)
  end

end






# test get_results_by_owner

# Tenant.all.each do |t|
#   on = t.owner_namespaces || []
#   data = CloudsightReader.get_results_by_owner(on)
# end

# test get_crawl_times

Image.all.each do |image|
  crawl_times = CloudsightReader.get_crawl_times(image)
  puts "#{image.name} : first crawl=#{crawl_times.first}, last crawl=#{crawl_times.last}"
end

puts "registered_namespaces : #{registered_namespaces.size}"
puts "namespaces : #{namespaces.size}"

# test auto assignment

# namespaces.each do |namespace, res|

#   puts "--------------- #{namespace} -----------------"
#   next if registered_namespaces.include? namespace
#   owner_namespace = res[:owner_namespace]
#   if t = owner_namespace_map[owner_namespace]
#     tenant_found = true
#     groups = t.groups
#   else
#     tenant_found = false
#     t = default_tenant
#     groups = []
#   end
#   tenant_id = t.id
#   puts "owner_namespace=#{owner_namespace}, tenant=#{t.name} #{tenant_found ? '' : '(default)'}"
#   # find group matched with pattern
#   group = assigned_group(res, t) if tenant_found
#   puts "===> #{group ? group.name : 'not found'}"
# end



# namespaces.each do |namespace, res|
#   puts "--------------- #{namespace} -----------------"
#   crawl_times = res[:crawl_times] || []
#   crawl_times.each do |crawl_time|
#     snapshot = CloudsightReader.get_result(namespace, crawl_time)
#   end
# end

#create tenant
#  --> create default group, create default group, load default rules
#  --> change default group to 1st group
#  --> create other group with random subset

# DescriptionDict.each do |name, description|
#   platform = nil
#   rule_group_name = nil
#   #script_path = ScriptDict[name]
#   script_path = "Comp.#{name}.py"
#   if md = name.match(/(\w+)\.(\d+)-\d+-[a-z]/)
#     platform = md[1]
#     rule_group_name = "ITCS104 Section #{md[2]}"
#   end
#   rule = Rule.new(name: name, description: description, script_path: script_path, long_description: description, rule_group_name: rule_group_name, platforms: platform)
#   fail rule.errors.full_messages.join(',') unless rule.save
#   puts rule.as_json
# end

# {'CITI' => 'citi_ns','TOYOTA' => 'toyota_ns','Walmart' => 'walmart_ns'}.each do |tenant_name, tenant_namespace|
#   tenant = Tenant.new(name: tenant_name, namespace: tenant_namespace)
#   fail tenant.errors.full_messages.join(',') unless tenant.save

#   ['ITCS104'].each_with_index do |group_name, j|
#     group = Group.new(name: group_name)
#     group.tenant_id = tenant.id
#     group.rule_id = Rule.all.map do |r|
#       r.id
#     end

#     group.default = true if j == 0
#     fail group.errors.full_messages.join(',') unless group.save

#     # arr = SentinelDocker::SearchAPI.get_tenant_rules(tenant_name, group_name)
#     # arr = arr.map {|r| r.id }
#     # SentinelDocker::SearchAPI.set_tenant_rules(tenant_name, group_name, arr.to_json)

#   end
# end
