  require 'sentinel-docker'
require 'sentinel-docker/docker_util'
require 'parallel'

module SentinelDocker
  module NsCrawler

    Log = SentinelDocker::Log

    Config = Hashie::Mash.new(
      rule_dir: '/home/ruleadmin/newrules',
      local_es_host: 'elasticsearch',
      local_es_port: '9200',
      local_es_log_enabled: false,
      crawled_data_index: "crawled_data",
      namespace_type: 'namespaces',
      history_type: 'history'
    )


    Local_Store = Elasticsearch::Client.new(hosts: [{ host: "#{Config.local_es_host}", port: "#{Config.local_es_port}" }], log: Config.local_es_log_enabled)

    begin
      SentinelDocker::Store.indices.create index: Config.crawled_data_index
    rescue
    end

    class NsCrawler

      MIN_WAIT_INTERVAL = 3 #second

      Log = SentinelDocker::Log

      def save(doc)

        if id
          result = Local_Store.update(
            index: Config.crawled_data_index,
            type: Config.namespace_type,
            id: id,
            refresh: true,
            body: { doc: doc, doc_as_upsert: true }
          )
        else
          result = Local_Store.index(
            index: Config.crawled_data_index,
            type: Config.namespace_type,
            refresh: true,
            body: doc
          )
        end
        
        result['_id']

      end



      def crawl_namespace(opt={:in_processes => 1})


        #namespace_type
        { 
          namespace: namespace, 
          last_update: last_update, 
          container_id: container_id, 
          image_id: image_id,
          type: namespace_type,
          crawl_times: crawl_times,
        }

        #history_type
        {
          begin_time: begin_time,
          end_time: end_time,
          exec_time: exec_time,
          success: true
        }

        # 1. get latest call to get_namespaces
        latest_call = get_latest_namespace_call
        namespaces = SentinelDocker::CloudsightUtil.get_namespaces(begin_time, end_time)
        puts "namespaces = #{namespaces}"
        new_containers = {}
        new_images = {}
        namespaces.each do |ns|
        puts "analyze namespace <#{ns}>"
        conf = parse_namespace(ns)
        if conf
          if conf[:container_id]
            new_containers[ns] = conf
          else
            new_images[ns] = conf
          end
        end
      end

        # 2. 
        #find latest time of crawling namespace
        #do get_namespaces and get_crawl_times
        # crawl_times(namespace, begin_time, end_time)
        # crawl_times(namespace, begin_time, end_time)
        # find new namespaces (every 5min) --> find crawl_times
        
        # get_namespaces(begin_time, end_time)
        # update crawl_times (every hour)

        #check if anything new
        #register new one
        #sleep

        loop 
          puts "searching namespaces from #{begin_time.iso8601} to #{end_time.iso8601}"
          namespaces = SentinelDocker::CloudsightUtil.get_namespaces(begin_time, end_time)
          puts "namespaces = #{namespaces}"
          new_containers = {}
          new_images = {}
          sleep(5*60)
        end

        Log.debug "[loop in run] finding requests..."

        jobs = SentinelDocker::RuleRunner.find_job(SentinelDocker::RuleRunner::Config.request_pool)

        #create namespace list
        namespaces = []
        jobs.each do |job|
          job_data = job.data
          job_key = job.jobkey
          klass = SentinelDocker::Models.const_get(job_data.type.camelize)
          rule_assign = klass.get(job_key)
          namespaces << rule_assign.container.namespace
        end

        crawl_times = {}
        namespaces.each_with_index do |ns, i|
          Log.debug "calling crawl_times api for namespace <#{ns}> (#{i}/#{namespaces.size})"
          times = SentinelDocker::DockerUtil.get_crawl_times(ns)
          crawl_times[ns] = times.empty? ? nil : times.first
        end

        jobs.each do |job|
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

        Log.debug "[loop in run] starting #{jobs.size} jobs in request pool"

        Parallel.each_with_index(jobs, opt) do |job, i|

          run_info = nil
          begin 
            
            request_id = Digest::MD5.hexdigest(job.id)

            Log.debug "#{request_id}: start run <#{job.jobkey}> (#{i}/#{jobs.size})"

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

      def query

        Log.debug "[loop in query] finding waiting jobs ..."

        jobs = SentinelDocker::RuleRunner.find_job(SentinelDocker::RuleRunner::Config.waiting_job_pool)

        Log.debug "[loop in query] starting #{jobs.size} jobs in waiting pool"

        Parallel.each(jobs, :in_processes => 1) do |job|

          run_info = nil

          begin 

            next if Time.now.to_i - job.timestamp < MIN_WAIT_INTERVAL

            #start query and create rule_run


            request_id = job.jobkey

            Log.debug "#{request_id}: start query"


            job_data = job.data
            run_info = job_data[:run_info]

            klass = SentinelDocker::Models.const_get(job_data.type.camelize)
            rule_assign = klass.get(job_data.rule_assign.id)
            user = job_data.user && job_data.user.id ? SentinelDocker::Models::User.get(job_data.user.id) : nil


            # query_result = do_es_query_by_request_id(request_id)
            #run_info[:output] = query_result 

            # klass = SentinelDocker::Models.const_get(job.data.type.camelize)
            # rule_assign = klass.get(job.jobkey)
            # user_id = job.data.user.id
            # user = user_id ? SentinelDocker::Models::User.get(user_id) : nil

            rule_run = SentinelDocker::DockerUtil.save_rule_run(rule_assign, run_info, user, false)

            Log.debug "time_for_crawl_times: #{run_info[:time_for_crawl_times]}"
            Log.debug "time_for_script_exec: #{run_info[:time_for_script_exec]}"

            if rule_run 
              Log.debug "#{request_id}: created rule_run"
              #complete exec
              SentinelDocker::RuleRunner.delete_job(SentinelDocker::RuleRunner::Config.waiting_job_pool, job.id)
              Log.debug "#{request_id}: deleted from waiting pool"
              Log.debug "time_for_save_rule_rune: #{run_info[:time_for_save_rule_rune]}"
            else
              Log.debug "#{request_id}: no result found in cloudsight yet : #{run_info.to_json}"
            end

          rescue => e
            Log.debug "query error: #{e.message}"
            Log.debug e.backtrace.join("\n")
            Log.debug "job=#{JSON.pretty_generate(job)}" if job
            Log.debug "run_info=#{JSON.pretty_generate(run_info)}" if run_info
          end

        end

      end

    end


    def self.request_new_run(rule_assign, user)
      Log.debug "register job for #{rule_assign.id}"
      put_job(Config.request_pool, rule_assign.id, {type: rule_assign.class.model_name.element, rule_assign: rule_assign, user: user})
    end

    private

    def self.run_rule(rule_assign, user=nil, debug=false)
      if check_if_no_conflict(rule_assign, user)
        register_new_run(rule_assign, user)
      else
        false
      end
    end

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

    def self.check_if_no_conflict(rule_assign, user)
      results = find_job(Config.request_pool, jobkey: rule_assign.id)
      results.size > 0 ? true : false
    end


  end
end

