# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "mtlumberjack"
  s.version = "0.0.20"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Jordan Sissel, Fabio Oliveira"]
  s.date = "2014-12-05"
  s.description = "Multi-tenant lumberjack log transport library"
  s.email = ["fabolive@us.ibm.com"]
  s.homepage = ""
  s.licenses = ["Apache 2.0"]
  s.require_paths = ["lib"]
  s.rubygems_version = "1.8.15"
  s.summary = "multi-tenant lumberjack log transport library, derived from jls-lumberjack"
  s.files = ["lib/mtlumberjack/client.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
