#!/usr/bin/env ruby

begin

  @method = "heat"
  @heat_url = nil
  @token = nil


  def log(level, msg)
    puts "<#{level.upcase}>|<#{@method}> #{msg}"
  end

  def get_stack_template(stack)
    log(:debug, "Entering method get_stack_template")
    require 'json'
    require 'rest_client'
    params = {
      :method => "GET",
      :url => "#{@heat_url}/stacks/#{stack.stack_name}/#{stack.id}/template",
      :headers => { :content_type => :json, :accept => :json, 'X-Auth-Token' => "#{@token}" }
    }
    response = RestClient::Request.new(params).execute
    log(:debug, "Raw Response: #{response.inspect}")
    json = JSON.parse(response)
    log(:debug, "JSON Response: #{json}")

    # this is a YAML-based template
    unless json['heat_template_version'].nil?
      log(:debug, "Template is YAML")
      log(:debug, "Exiting method get_stack_template")
      return json.to_yaml
    else
      log(:debug, "Template is JSON")
      log(:debug, "Exiting method get_stack_template")
      return JSON.pretty_generate(json)
    end
  end

  def get_stack_resources(stack)
    log(:debug, "Entering method get_stack_resources")
    require 'json'
    require 'rest_client'
    server_ids = []
    params = {
      :method => "GET",
      :url => "#{@heat_url}/stacks/#{stack.stack_name}/#{stack.id}/resources",
      :headers => { :content_type => :json, :accept => :json, 'X-Auth-Token' => "#{@token}" }
    }
    json = JSON.parse(RestClient::Request.new(params).execute)

    json['resources'].each {|resource|
      log(:debug, "Checking resource #{resource['resource_name']}")
      params = {
        :method => "GET",
        :url => "#{resource['links'][0]['href']}",
        :headers => { :content_type => :json, :accept => :json, 'X-Auth-Token' => "#{@token}" }
      }
      resource_json = JSON.parse(RestClient::Request.new(params).execute)
      log(:debug, "Resource Details: #{resource_json.inspect}")
      case resource_json['resource']['resource_type']
        when "AWS::EC2::Instance"
          server_ids.push(resource_json['resource']['physical_resource_id'])
        when "OS::Nova::Server"
          server_ids.push(resource_json['resource']['physical_resource_id'])
      end
    }
    log(:info, "Found #{server_ids.inspect} instances as part of this stack")
 
    log(:debug, "Exiting method get_stack_resources")
  end

  gem 'fog', '>=1.22.0'
  require 'fog'

  conn = Fog::Orchestration.new({
    :provider => 'OpenStack',
    :openstack_api_key => ENV['OS_PASSWORD'],
    :openstack_username => ENV['OS_USERNAME'],
    :openstack_auth_url => ENV['OS_AUTH_URL'] + "tokens",
    :openstack_tenant => ENV['OS_TENANT_NAME']
  })

  @token = conn.auth_token
  @heat_url = conn.instance_variable_get(:@openstack_management_url)

   template_file = ARGV.first
   subtemplate = ARGV.last
   file = File.open(template_file)
   template_body = ""
   file.each {|line| template_body << line}

   file = File.open(subtemplate)
   subfile_template = ""
   file.each {|line| subfile_template << line}

   stack_props = conn.create_stack("rubytest", { :template => template_body, 
                                             :files => { "file://#{subtemplate}" => subfile_template }  }).body['stack']
   stack = conn.stacks.find_by_id(stack_props['id'])
   log(:info, "Stack: #{stack.inspect}")


rescue => err
  log(:error, "Caught error #{err}\n #{err.backtrace.join("\n --> ")}")
end

