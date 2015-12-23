# =================================================================
# Licensed Materials - Property of IBM
#
# (c) Copyright IBM Corp. 2014 All Rights Reserved
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# =================================================================
require_relative 'support/coverage'

require 'tmpdir'
require 'sentinel/util'

include Sentinel::Util

describe Sentinel::Util do
  it 'extracts a policy zip file and returns the policy name' do
    name = extract_files(File.expand_path('../support/policy_iptables.zip', __FILE__), Dir.tmpdir)
    expect(name).to eql('policy_iptables')
  end
end
