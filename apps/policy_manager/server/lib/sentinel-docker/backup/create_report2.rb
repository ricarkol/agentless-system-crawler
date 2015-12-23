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
require 'rack/test'
require 'json'
require 'erb'
require 'sentinel-docker/load_rules2'

include Rack::Test::Methods
include SentinelDocker::Models


SentinelDocker::Config.db.index_name = 'testing'

def app
  SentinelDocker::API::Root
end

pedigree = {}
get "api/images"
images = JSON.parse(last_response.body)
images.each do |image|
  docker_image_id = image['image_id'][0,12]
  history = SentinelDocker::AutoLoadUtil.get_image_history(docker_image_id)

  child = nil
  history['history'].each do |h|
    parent = h['Id'][0,12]
    pedigree[child] = parent if child
    child = parent
  end
end


system_status = {}

get 'api/rules'
system_status['rules'] 

rules = JSON.parse(last_response.body).map do |r|
  r['script_path']
end

rules.select! do |script_path|
  /^Comp-.*/ =~ script_path 
end

rules.sort!

system_status['rules'] = rules




image_created = {}

get 'api/containers'
containers = JSON.parse(last_response.body)
# puts containers


containers.each do |container|

  container_status = {}

  _container_id = container['id']
  container_status['docker_container_id'] = container['container_id']  #docker_container_id
  container_status['created'] = container['created']!=0 ? Time.at(container['created']).strftime("%Y-%m-%d %H:%M:%S") : ""
  image_id = container['image_id']
  get "api/images/#{image_id}"
  image = JSON.parse(last_response.body)
  docker_image_id = image['image_id']
  container_status['docker_image_id'] = docker_image_id
  image_created[docker_image_id] = image['created']!=0 ? Time.at(image['created']).strftime("%Y-%m-%d %H:%M:%S") : ""

  #  puts "image=#{image}"
  get "api/containers/#{_container_id}/rules"
  container_rules = JSON.parse(last_response.body)
  #  puts "container_rules=#{container_rules}"

  check_status = {}
  container_rules.each do |cr|

    rule_assign_def_id = cr['rule_assign_def_id']
    get "/api/rule_assign_defs/#{rule_assign_def_id}"
    rule_assign_def = JSON.parse(last_response.body)
    rule_id = rule_assign_def['rule_id']
    get "/api/rules/#{rule_id}"
    rule = JSON.parse(last_response.body)
    script_path = rule['script_path']  #script_path

    _container_rule_id = cr['id']
    get "api/containers/#{_container_id}/rules/#{_container_rule_id}/runs"
    rule_runs = JSON.parse(last_response.body)
    unless rule_runs.empty?
      rr = rule_runs.first
      check_status[script_path] = rr
    end

  end
  container_status['check_status'] = check_status

  image_status = system_status[container_status['docker_image_id']] || []
  image_status << container_status
  system_status[container_status['docker_image_id']] = image_status

end


#puts JSON.pretty_generate(system_status)

template = <<EOS
  <html xml:lang="en" lang="en">
  <head>
  <title>Test</title>
  <style type="text/css" media="screen">
  body {
    font-family: sans-serif;
    padding: 10px;
  }
  h2 {
    font-size: 16pt;
    color: #4B75B9;
    margin-top: 25px;
    margin-bottom: 7px;
    border-bottom: 1px solid #4B75B9;
  }
  p,div,table,td,tr {
    font-family: sans-serif;
    margin: 0px;
  }

  table {
    font-size: 10pt;
    font-family: sans-serif;
  }
  td.tag {
    padding: 3px;
    font-weight: bold;
    width: 100px;
    height: 30px;
    background-color: #D5E0F1;
  }
  tr.stat {
    height: 40px;
  }
  td.fname {
    padding: 5px;
    background-color: #D5E0F1;
  }
  td.stat {
    padding: 3px;
    width: 100px;
  }
  td.stat p {
    padding: 1px;
    margin: 1px;
  }
  .stat_pass {
    background-color: #81D674;
  }
  .stat_fail {
    background-color: #E38692;
  }
  .stat_none {
    background-color: #E0E0E0;
    color: #999;
    text-align: center;
  }
  .stat_notags {
    background-color: #F0F0F0;
    color: #555;
    border: 1px solid #AAA;
  }

  .stat_notyet {
    background-color: #EBF182;
  }
  div.detail {
    margin: 10px;
  }
  div.detail div {
    margin: 3px;
    padding: 6px;
  }
  div.detail div h3 {
    margin: 3px;
    padding: 0px;
  }
  div.detail p {
    font-family: monospace;
    margin: 2px;
    padding: 0px;
  }
  .hide {
    display: none;
  }
  div.env p {
    margin: 3px;
  }
  span.btn {
    border: 2px solid #8BA7D5;
    font-weight: bold;
    padding: 2px;
    color: #8BA7D5;
    font-size: 10pt;
  }
#menu div {
  position: relative;
}

.arrow_box {
  display: none;
  position: absolute;
  padding: 16px;
  -webkit-border-radius: 8px;
  -moz-border-radius: 8px;  
  border-radius: 8px;
  background: #333;
  color: #fff;
}

.arrow_box:after {
  position: absolute;
  bottom: 100%;
  left: 50%;
  width: 0;
  height: 0;
  margin-left: -10px;
  border: solid transparent;
  border-color: rgba(51, 51, 51, 0);
  border-bottom-color: #333;
  border-width: 10px;
  pointer-events: none;
  content: " ";
}


  </style>
  <script src="http://code.jquery.com/jquery-1.11.0.min.js"></script>
  </head>
  <body>
  <h1>S&C Service for Docker Cloud: Check Status</h1>
  <div id="vars" class="hide">
  </div>
  <h2>Results (as of <%= Time.now.strftime("%e %b %Y %H:%M:%S%p %Z") %>) </h2>
  <table><thead><tr>
  <td class="tag">Image ID</td>
  <td class="tag">Container ID</td>
  <td class="tag">Created</td>
  <% system_status['rules'].each do |script_path| %>
  <td class="tag">
    <p><%= script_path.split('.')[0] %></p>
    <p><%= script_path.split('.')[1] %></p>
  </td>
  <% end %>
  </tr></thead>
  <% system_status.each do |image_id, image_status| 
       next if image_id == 'rules' 
       num_container = image_status.size
       first_row = true
  %>
  <tbody>
  <%
       image_status.sort_by { |cs| cs['created'] }.each do |container_status| 
         docker_container_id = container_status['docker_container_id']
         created = container_status['created']


      %> 
      <tr class="stat">
      <% if first_row %>
      <td class="fname" rowspan="<%= num_container %>">
        <p><%= image_id %></p>
        <p>created : <%= image_created[image_id] %></p>
        <p>parent : <%= pedigree[image_id[0,12]] ? pedigree[image_id[0,12]] : "" %></p>
      </td>
      <% 
         first_row=false
      end %>
      <td class="fname">
        <span><%=docker_container_id %></span>
      </td>
      <td class="fname">
        <span><%= created %></span>
      </td>
      <% system_status['rules'].each do |script_path| 
           cs = container_status['check_status']
           if cs
             rrr = cs[script_path]
            else
              rrr = nil
            end
           if rrr
              cell = rrr['status']
              cell_id = rrr['id']
            else
              cell = 'N/A'
              cell_id = "" 
            end
            class_value = "stat"
            case cell
            when 'PASS' then
              class_value << ' stat_pass'
            when 'FAIL' then
              if rrr['output'] =~ /^no crawled data available/
                class_value << ' stat_notyet'  
              else
                class_value << ' stat_fail'
              end
            else
              class_value << ' stat_none'
            end
      %>
      <td id="<%= cell_id %>" class="<%= class_value %>">
      <span><%= cell %></span>
      <p class="arrow_box"><%=rrr %></p>
      </td>
      <% end %>
    </tr>
    <% end %>
    </tbody>
  <% end %>
  </table>
  </body>
  <script>
  $(function () {
  $('span').hover(function() {
    $(this).next('p').show();
  }, function(){
    $(this).next('p').hide();
  });
});
  </script>
  </html>
EOS

erb = ERB.new(template)
puts output = erb.result(binding)

