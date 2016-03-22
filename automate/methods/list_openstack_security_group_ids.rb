=begin
  list_openstack_securitygroup_refs.rb

  Author: Nate Stephany <nate@redhat.com, Kevin Morey <kmorey@redhat.com>

  Description: list OpenStack security groups based on tag category assigned to group

-------------------------------------------------------------------------------
   Copyright 2016 Kevin Morey <kmorey@redhat.com>

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-------------------------------------------------------------------------------
=end

def log_and_update_message(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def dump_root()
  log_and_update_message(:info, "Begin $evm.root.attributes")
  $evm.root.attributes.sort.each { |k, v| log_and_update_message(:info, "\t Attribute: #{k} = #{v}")}
  log_and_update_message(:info, "End $evm.root.attributes")
  log_and_update_message(:info, "")
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

def get_provider(provider_id=nil)
  if provider_id.blank?
    $evm.root.attributes.detect { |k,v| provider_id = v if k.end_with?('provider_id') } rescue nil
  end
  provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).find_by_id(provider_id)
  if provider.nil?
    provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).first
    log_and_update_message(:info, "Found provider: #{provider.name} via default method") if provider
  else
    log_and_update_message(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}") if provider
  end
  provider ? (return provider) : (return nil)
end

def get_current_group_rbac_array
  rbac_array = []
  unless @user.current_group.filters.blank?
    @user.current_group.filters['managed'].flatten.each do |filter|
      next unless /(?<category>\w*)\/(?<tag>\w*)$/i =~ filter
      rbac_array << {category=>tag}
    end
  end
  log_and_update_message(:info, "rbac filters: #{rbac_array}")
  rbac_array
end

def get_user
  user_search = $evm.root['dialog_userid'] || $evm.root['dialog_evm_owner_id']
  user = $evm.vmdb('user').find_by_id(user_search) ||
    $evm.vmdb('user').find_by_userid(user_search) ||
    $evm.root['user']
  user
end

def get_tenant(tenant_category=nil, tenant_id=nil)
  # get the cloud_tenant id from $evm.root if already set
  $evm.root.attributes.detect { |k,v| tenant_id = v if k.end_with?('cloud_tenant') } rescue nil
  tenant = $evm.vmdb(:cloud_tenant).find_by_id(tenant_id)
  log_and_update_message(:info, "Found tenant: #{tenant.name} via tenant_id: #{tenant.id}") if tenant

  unless tenant
    # get the tenant name from the group tenant tag
    group = $evm.root['user'].current_group
    tenant_tag = group.tags(tenant_category).first rescue nil
    tenant = $evm.vmdb(:cloud_tenant).find_by_name(tenant_tag) rescue nil
    log_and_update_message(:info, "Found tenant: #{tenant.name} via group: #{group.description} tagged_with: #{tenant_tag}") if tenant
  end

  # set to true to default to the admin tenant
  use_default = true
  unless tenant
    tenant = $evm.vmdb(:cloud_tenant).find_by_name('admin') if use_default
    log_and_update_message(:info, "Found tenant: #{tenant.name} via default method") if tenant && use_default
  end
  tenant ? (return tenant) : (return nil)
end

begin
  dump_root()

  # initializing a couple of hashes
  # dialog_hash is what actually contains the contents of the dynamic dropdown
  dialog_hash = {}
  options_hash = {}

  # gathering some basic variables for use here and there
  @user = get_user
  @rbac_array = get_current_group_rbac_array
  provider_id =  $evm.root['dialog_provider_id'] || options_hash['provider_id']
  @provider = get_provider(provider_id)
  log_and_update_message(:info, "provider: #{@provider.name} provider id: #{@provider.id}")

  # change this to actually pass in tenant if we have a tagging or tenant plan in place
  tenant = get_tenant()

  openstack_neutron = get_fog_object('Network')
  security_group_list = openstack_neutron.list_security_groups.body["security_groups"].select { |s| s["tenant_id"] == tenant.ems_ref }
  security_group_list.each do |sg|
  	dialog_hash[sg["id"]] = "#{sg["name"]}"
  end

  if dialog_hash.blank?
    dialog_hash[''] = "< No Security Groups found. >"
  else
    #dialog_hash[''] = "< choose a VM >"
    $evm.object['default_value'] = dialog_hash.find { |k,v| v == "default" }[0]
    log_and_update_message(:info, "dialog_hash contents: #{dialog_hash.inspect}")
  end

  $evm.object['values'] = dialog_hash
  log_and_update_message(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")
end

