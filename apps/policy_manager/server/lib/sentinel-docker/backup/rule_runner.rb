require 'sentinel-docker'
require 'sentinel-docker/docker_util'
require 'sentinel-docker/cloudsight_util'
require 'parallel'

module SentinelDocker
  module RuleRunner

    # User = Models::User
    # Container = Models::Container
    # Image = Models::Image
    # ImageRule = Models::ImageRule
    # ContainerRule = Models::ContainerRule
    # ContainerRuleRun = Models::ContainerRuleRun
    # Rule = Models::Rule
    # RuleAssignDef = Models::RuleAssignDef

    Log = SentinelDocker::Log

    Config = Hashie::Mash.new(
      rule_dir: '/home/ruleadmin/newrules',
      local_es_host: 'elasticsearch',
      local_es_port: '9200',
      local_es_log_enabled: false,
      local_job_index: 'local_jobs',
      request_pool: 'requests',
      running_job_pool: 'running',
      waiting_job_pool: 'waiting'
    )

    MIN_WAIT_INTERVAL = 3 #second
    MAX_FAILURE = 5
    MAX_RUNNIG_TIME = 5*60 #second

    Local_Store = Elasticsearch::Client.new(hosts: [{ host: "#{Config.local_es_host}", port: "#{Config.local_es_port}" }], log: Config.local_es_log_enabled)

    begin
      Local_Store.indices.create index: Config.local_job_index
    rescue
    end

    # class RunMonitor

    #   Log = SentinelDocker::Log

    def self.clear_running_job
      jobs = SentinelDocker::RuleRunner.find_job(SentinelDocker::RuleRunner::Config.running_job_pool)
      jobs.each do |job|
        if Time.now.to_i - job.timestamp > MAX_RUNNIG_TIME
          begin
            # SentinelDocker::RuleRunner.put_job(SentinelDocker::RuleRunner::Config.waiting_job_pool, job.data.request_id, job.data)
            SentinelDocker::RuleRunner.delete_job(SentinelDocker::RuleRunner::Config.running_job_pool, job.id)
            Log.debug "cleared job <job.id> in running pool"
          rescue => e
            Log.error "error in clear running job: #{e.message}"
            Log.error e.backtrace.join("\n")
          end
        else
          Log.debug "keep job <job.id> in running pool"
        end
      end
    end


    def self.run(opt={:in_processes => 0})

      Log.debug "[loop in run] finding requests..."

      jobs = SentinelDocker::RuleRunner.find_job(SentinelDocker::RuleRunner::Config.request_pool)

      #create namespace list
      namespaces = []
      valid_jobs = []
      targets = []
      jobs.each do |job|
        job_data = job.data
        job_key = job.jobkey
        klass = SentinelDocker::Models.const_get(job_data.type.camelize)
        rule_assign = klass.get(job_key)
        target = "#{rule_assign.container.id}/#{rule_assign.rule_assign_def.id}"
        if rule_assign == nil
          Log.error "request #{job_key} is invalid (fail to find rule to be executed)"
          SentinelDocker::RuleRunner.delete_job(SentinelDocker::RuleRunner::Config.request_pool, job.id)
        elsif targets.include? target
          Log.debug "trimed duplicate request #{job_key}"
          SentinelDocker::RuleRunner.delete_job(SentinelDocker::RuleRunner::Config.request_pool, job.id)
        else
          namespaces << rule_assign.container.namespace
          valid_jobs << job
          targets << target
        end
      end

      crawl_times = {}
      namespaces.each_with_index do |ns, i|
        Log.debug "calling crawl_times api for namespace <#{ns}> (#{i}/#{namespaces.size})"
        times = SentinelDocker::DockerUtil.get_crawl_times(ns)
        crawl_times[ns] = times.empty? ? nil : times.first
      end

      valid_jobs.each do |job|
        job_data = job.data
        job_key = job.jobkey
        klass = SentinelDocker::Models.const_get(job_data.type.camelize)
        rule_assign = klass.get(job_key)
        ns = rule_assign.container.namespace
        job_data[:crawl_time] = crawl_times[ns]
        result = SentinelDocker::RuleRunner.update_job(SentinelDocker::RuleRunner::Config.request_pool, job.id, job_data)
        Log.debug "job successfully updated : #{result.to_json}"          
      end

      # jobs = jobs.shuffle[0, [100, jobs.size].min]

      Log.debug "[loop in run] starting #{valid_jobs.size} jobs in request pool"

      Parallel.each_with_index(valid_jobs, opt) do |job, i|

        run_info = nil
        begin 
          
          request_id = Digest::MD5.hexdigest(job.id)

          Log.debug "#{request_id}: start run <#{job.jobkey}> (#{i}/#{valid_jobs.size})"

          job_data = job.data
          job_key = job.jobkey

          klass = SentinelDocker::Models.const_get(job_data.type.camelize)
          rule_assign = klass.get(job_key)
          user = job_data.user && job_data.user.id ? SentinelDocker::Models::User.get(job_data.user.id) : nil
          
          running_job_id = SentinelDocker::RuleRunner.take_job(SentinelDocker::RuleRunner::Config.request_pool, SentinelDocker::RuleRunner::Config.running_job_pool, job)
          Log.debug "#{request_id}: move from request pool to running pool"


          run_info = SentinelDocker::DockerUtil.trigger_script_execution(rule_assign, job_data.crawl_time, request_id, user)
          job_data[:run_info] = run_info
          job_data[:rule_assign] = rule_assign
          job_data[:request_id] = request_id

          SentinelDocker::RuleRunner.delete_job(SentinelDocker::RuleRunner::Config.running_job_pool, running_job_id)
          Log.debug "#{request_id}: delete from running pool"

          SentinelDocker::RuleRunner.put_job(SentinelDocker::RuleRunner::Config.waiting_job_pool, request_id, job_data)
          Log.debug "#{request_id}: put to waiting pool"
        rescue => e
          Log.debug "run error: #{e.message}"
          Log.debug e.backtrace.join("\n")
          Log.debug "job=#{JSON.pretty_generate(job)}" if job
          Log.debug "run_info=#{JSON.pretty_generate(run_info)}" if run_info
        end

      end

    end

    def self.query(opt={:in_processes => 0})

      Log.debug "[loop in query] finding waiting jobs ..."
      jobs = SentinelDocker::RuleRunner.find_job(SentinelDocker::RuleRunner::Config.waiting_job_pool)
      Log.debug "[loop in query] starting #{jobs.size} jobs in waiting pool"

      Parallel.each(jobs, opt) do |job|

        run_info = nil
        begin 
          next if Time.now.to_i - job.timestamp < MIN_WAIT_INTERVAL
          #start query and create rule_run
          request_id = job.jobkey
          Log.debug "#{request_id}: start query"

          job_data = job.data
          run_info = job_data[:run_info]

          if run_info[:exit_code] == 0
            query_result = SentinelDocker::CloudsightUtil.get_result(request_id)
            unless query_result
              failure_count = job_data[:failure] ? job_data[:failure].to_i + 1 : 1
              if failure_count < MAX_FAILURE
                job_data[:failure] = failure_count
                result = SentinelDocker::RuleRunner.update_job(SentinelDocker::RuleRunner::Config.waiting_job_pool, job.id, job_data)
                Log.debug "result for #{request_id} cannot be found in Cloudsight ES yet (#{failure_count}/#{MAX_FAILURE})"
              else
                Log.error "#{request_id}: fail to find result in cloudsignt #{MAX_FAILURE} times"
                Log.error "#{request_id}: run_info=#{JSON.pretty_generate(run_info)}"
                #complete exec
                SentinelDocker::RuleRunner.delete_job(SentinelDocker::RuleRunner::Config.waiting_job_pool, job.id)
                Log.debug "#{request_id}: deleted from waiting pool"
              end
              next
            end
            run_info[:output] = query_result
            run_info[:valid_json] = true        
          end

          klass = SentinelDocker::Models.const_get(job_data.type.camelize)
          rule_assign = klass.get(job_data.rule_assign.id)
          user = job_data.user && job_data.user.id ? SentinelDocker::Models::User.get(job_data.user.id) : nil

          # run_info[:output] = query_result 

          # klass = SentinelDocker::Models.const_get(job.data.type.camelize)
          # rule_assign = klass.get(job.jobkey)
          # user_id = job.data.user.id
          # user = user_id ? SentinelDocker::Models::User.get(user_id) : nil

          rule_run = SentinelDocker::DockerUtil.save_rule_run(rule_assign, run_info, user)

          Log.debug "time_to_prepare_file_content: #{run_info[:time_to_prepare_file_content]}"
          Log.debug "time_for_script_exec: #{run_info[:time_for_script_exec]}"

          if rule_run 
            Log.debug "#{request_id}: created rule_run"
            #complete exec
            SentinelDocker::RuleRunner.delete_job(SentinelDocker::RuleRunner::Config.waiting_job_pool, job.id)
            Log.debug "#{request_id}: deleted from waiting pool"
            SentinelDocker::SCServerControl.request_page_update [:compliance]

          else
            Log.debug "#{request_id}: no result found in cloudsight yet"
          end

        rescue => e
          Log.debug "query error: #{e.message}"
          Log.debug e.backtrace.join("\n")
          Log.debug "job=#{JSON.pretty_generate(job)}" if job
          Log.debug "run_info=#{JSON.pretty_generate(run_info)}" if run_info
        end

      end

    end

    def self.request_new_run(rule_assign, user)
      req_id = nil
      if check_if_already_requested(rule_assign)
        Log.debug "job for #{rule_assign.id} is already running"
      else 
        Log.debug "register job for #{rule_assign.id}"
        id = put_job(Config.request_pool, rule_assign.id, {type: rule_assign.class.model_name.element, rule_assign: rule_assign, user: user})
        req_id = Digest::MD5.hexdigest(id)
      end
      req_id
    end

    private

    # def self.run_rule(rule_assign, user=nil, debug=false)
    #   results = find_job(Config.request_pool, jobkey: rule_assign.id)
    #   if results.size > 0 
    #     register_new_run(rule_assign, user)
    #   else
    #     false
    #   end
    # end

    def self.find_job(pool_type, opt=nil)
      if opt
        opt = {term: opt}
      else
        opt = {match_all: {}}
      end
      param = {
        index: Config.local_job_index,
        type: pool_type,
        body: {
          query: opt,
          size: 1000
        }
      }

      response = Hashie::Mash.new(Local_Store.search(param))
      results = response.hits.hits.map do |hit|
        hit._source.merge(id: hit._id)
      end

    end

    def self.check_if_already_requested(rule_assign)
      
      param = {
        index: Config.local_job_index,
        type: [Config.request_pool,Config.running_job_pool,Config.waiting_job_pool].join(','),
        body: {
          query: {match: {'data.rule_assign.id' => rule_assign.id}},
          fields: ['data.rule_assign.id', 'timestamp'],
          size: 1
        }
      }

      response = Hashie::Mash.new(Local_Store.search(param))
      response.hits.hits.empty? ? false : true

    end




    def self.get_job(pool_type, id)
      param = {
        index: Config.local_job_index,
        type: pool_type,
        body: {
          query: {
            ids: { values: [id] }
          }
        }
      }

      response = Hashie::Mash.new(Local_Store.search(param))
      results = response.hits.hits.map do |hit|
        hit._source.merge(id: hit._id)
      end
      results.first
    end

    def self.put_job(pool_type, jobkey, obj)

      result = Local_Store.index(
        index: Config.local_job_index,
        type: pool_type,
        refresh: true,
        body: {jobkey: jobkey, data: obj, timestamp: Time.now.to_i}.to_json
      )
      result['_id']

    end

    def self.update_job(pool_type, id, obj)

      result = Local_Store.update(
        index: Config.local_job_index,
        type: pool_type,
        id: id,
        refresh: true,
        body: { doc: {data: obj}, doc_as_upsert: true }
      )

      result

    end

    def self.delete_job(pool_type, id)

      SentinelDocker::Store.delete(
        index: Config.local_job_index,
        type: pool_type,
        refresh: true,
        id: id
      )

    end

    def self.take_job(pool_type_before, pool_type_after, job = nil)

      unless job

        param = {
          index: Config.local_job_index,
          type: pool_type_before,
          body: {
            query: {
              match_all: {},
              sort: 'timestamp:asc',
              size: 1
            }
          }
        }

        response = Hashie::Mash.new(Local_Store.search(param))
        results = response.hits.hits.map do |hit|
          hit._source.merge(id: hit._id)
        end

        job = results.first
      
      end

      id = put_job(pool_type_after, job.jobkey, job.data)
      delete_job(pool_type_before, job.id)
      
      id

    end

  end
end

