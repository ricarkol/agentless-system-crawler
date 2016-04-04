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

DescriptionDict.each do |name, description|
  platform = nil
  rule_group_name = nil
  #script_path = ScriptDict[name]
  script_path = "Comp.#{name}.py"
  if md = name.match(/(\w+)\.(\d+)-\d+-[a-z]/)
    platform = md[1]
    rule_group_name = "ITCS104 Section #{md[2]}"
  end
  rule = Rule.new(name: name, description: description, script_path: script_path, long_description: description, rule_group_name: rule_group_name, platforms: platform)
  fail rule.errors.full_messages.join(',') unless rule.save
  puts rule.as_json
end

{'CITI' => 'citi_ns','TOYOTA' => 'toyota_ns','Walmart' => 'walmart_ns'}.each do |tenant_name, tenant_namespace|
  tenant = Tenant.new(name: tenant_name, owner_namespace: [tenant_namespace])
  fail tenant.errors.full_messages.join(',') unless tenant.save

  ['ITCS104'].each_with_index do |group_name, j|
    group = Group.new(name: group_name)
    group.tenant_id = tenant.id
    group.rule_id = Rule.all.map do |r|
      r.id
    end

    group.default = true if j == 0
    fail group.errors.full_messages.join(',') unless group.save

  end
end

