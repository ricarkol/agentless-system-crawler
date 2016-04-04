# coding: utf-8
# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

# Save off last revision
last_rev = `git rev-parse --short HEAD`.chomp
IO.write('.last_rev', last_rev) unless last_rev.include?('fatal:') || last_rev.include?('command not found')

require 'sentinel-docker/version'

Gem::Specification.new do |spec|
  spec.name          = 'sentinel'
  spec.version       = SentinelDocker::VERSION
  spec.authors       = ['Renier Morales']
  spec.email         = ['renierm@us.ibm.com']
  spec.summary       = %q{Security & Compliance service for Docker}
  spec.description   = IO.read('README.md')
  spec.homepage      = 'https://gitlab.democentral.ibm.com/mms/sentinel'
  spec.license       = 'IBM'

  spec.files         = `git ls-files`.split($/) + (File.exists?('.last_rev') ? ['.last_rev']  : [])
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'grape', '~> 0.7.0'
  spec.add_dependency 'grape-entity', '~> 0.4.2'
  spec.add_dependency 'hashie', '~> 3.0.0'
  spec.add_dependency 'softlayer_api', '~> 2.1.0'
  spec.add_dependency 'elasticsearch', '~> 1.0.2'
  spec.add_dependency 'activemodel', '~> 4.1.1'
  spec.add_dependency 'activesupport', '~> 4.1.1'
  spec.add_dependency 'rack', '~> 1.5.2'
  spec.add_dependency 'ruby-openid', '~> 2.5.0'
  spec.add_dependency 'erubis', '~> 2.7.0'
  spec.add_dependency 'rubyzip', '~> 1.1.6'
  spec.add_dependency 'net-ssh', '~> 2.9.1'
  spec.add_dependency 'parallel', '~> 1.4.1'
#  spec.add_dependency 'snappy', '~> 0.0.11'
  spec.add_dependency 'poseidon', '~> 0.0.5'

  spec.add_dependency 'port_vul', '~> 0.1.0'
  spec.add_dependency 'scdocker_utils', '~> 0.1.0'
  spec.add_dependency 'faye-websocket', '~> 0.9.2'

  spec.add_development_dependency 'bundler', '~> 1.6'
  spec.add_development_dependency 'rake', '~> 10.1'
  spec.add_development_dependency 'guard-rack', '~> 1.4'
  spec.add_development_dependency 'rack-test', '~> 0.6.2'
  spec.add_development_dependency 'rubocop', '~> 0.23.0'
  spec.add_development_dependency 'rspec', '~> 2.14'
  spec.add_development_dependency 'license_finder', '~> 1.0.0'
  spec.add_development_dependency 'pry', '~> 0.10.0'
  spec.add_development_dependency 'stamper', '~> 0.1.1'
  spec.add_development_dependency 'simplecov', '~> 0.7.1'
end
