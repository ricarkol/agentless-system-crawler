# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"

# A null output. This is useful for testing logstash inputs and filters for
# performance.
class LogStash::Outputs::Mtlumberjack < LogStash::Outputs::Base
  config_name "mtlumberjack"
  milestone 3

  public
  def register
  end # def register

  public
  def receive(event)
  end # def event
end # class LogStash::Outputs::Null
