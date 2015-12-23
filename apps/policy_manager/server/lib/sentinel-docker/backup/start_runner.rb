require 'sentinel-docker'
require 'sentinel-docker/docker_util'
require 'sentinel-docker/rule_runner'
require 'parallel'
require 'profiler'

RubyVM::InstructionSequence.compile_option = {
  :trace_instruction => true,
  :specialized_instruction => false
}

#Profiler__::start_profile

Log = SentinelDocker::Log

run_thread = nil
query_thread = nil
begin

  # user = SentinelDocker::Models::User.all.first
  # map = {}
  # SentinelDocker::Models::Container.all.each do |container|
  #   container.container_rules.each do |cr|
  #     map[cr.id] = cr.container_rule_runs.size
  #     SentinelDocker::RuleRunner.request_new_run(cr, user)
  #   end
  #   break
  # end

  run_thread = Thread.new do
    Log.debug 'start run thread'
    loop {
      SentinelDocker::RuleRunner.run(:in_processes => 1)

      Log.debug "[loop in run] waiting next loop : #{Time.now.iso8601}"
      sleep(5)
    }
    Log.debug 'end run thread'
  end

  query_thread = Thread.new do
    Log.debug 'start query thread'
    loop {
      SentinelDocker::RuleRunner.query(:in_processes => 1)
      Log.debug "[loop in query] waiting next loop : #{Time.now.iso8601}" 
      sleep(30)
    }
    Log.debug 'end query thread'
  end


  run_thread.join
  query_thread.join

rescue => e
  Log.debug "run error: #{e.message}"
  Log.debug e.backtrace.join("\n")
ensure

  Thread.kill(run_thread) if run_thread
  Thread.kill(query_thread) if query_thread
  Log.debug "all threads have been terminated safely"
  # Profiler__::print_profile(STDERR)
  # Profiler__::stop_profile

end
