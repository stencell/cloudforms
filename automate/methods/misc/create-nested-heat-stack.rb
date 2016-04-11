#!/usr/bin/env ruby


def log(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def get_fog_object(type='Compute', tenant='admin', endpoint='adminURL')
  require 'fog'
  (@provider.api_version == 'v2') ? (conn_ref = '/v2.0/tokens') : (conn_ref = '/v3/auth/tokens')
  (@provider.security_protocol == 'non-ssl') ? (proto = 'http') : (proto = 'https')

  connection_hash = {
    :provider => 'OpenStack',
    :openstack_api_key => @provider.authentication_password,
    :openstack_username => @provider.authentication_userid,
    :openstack_auth_url => "#{proto}://#{@provider.hostname}:#{@provider.port}#{conn_ref}",
    :openstack_tenant => tenant,
  }
  connection_hash[:openstack_endpoint_type] = endpoint if type == 'Identity'
  # if the openstack environment is using keystone v3, add two keys to hash and replace the auth_url
  if @provider.api_version == 'v3'
    connection_hash[:openstack_domain_name] = 'Default'
    connection_hash[:openstack_project_name] = tenant
    connection_hash[:openstack_auth_url] = "#{proto}://#{@provider.hostname}:35357/#{conn_ref}"
  end
  return Object::const_get("Fog").const_get("#{type}").new(connection_hash)
end

$evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

nested_templates = {}
log(:info, "created empty hash for #{nested_templates.inspect}")
# in the master template, the "type" file name needs to be nested_template_xxxxx
# or whatever you set the template_regex search to
# these templates must exist in cloudforms
# TODO: add free form so you can paste in a script that is referenced in master template
template_regex = /dialog_nested_template\w/

$evm.root.attributes.each { |k,v| nested_templates[k] = ($evm.vmdb(:orchestration_template).all.detect \
                                                         { |t| t.id == v.to_i }.content) if k.to_s =~ template_regex }
log(:info, "populated nested_templates hash with values: #{nested_templates.inspect}")
nested_templates.clone.each { |k,v| nested_templates[k.sub(/dialog_nested_template_/, '')] = nested_templates.delete(k) }
log(:info, "stripped prefixes from keys in nested_templates: #{nested_templates.inspect}")
nested_templates.clone.each { |k,v| nested_templates[k.sub(/$/, '.yaml')] = nested_templates.delete(k) }
log(:info, "appended .yaml to nested template name to make it all work: #{nested_templates.inspect}")

openstack_heat = get_fog_object('Orchestration')
new_stack = openstack_heat.create_stack("test-hpc", {
                                          :template => template_body,
                                          :files => nested_templates
})

log(:info, "Stack: #{new_stack.inspect}")
log(:info, "Created stack #{new_stack.body['name']}")
