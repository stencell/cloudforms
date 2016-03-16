=begin
  list_openstack_vm_names.rb

  Author: Nate Stephany <nate@redhat.com>, Kevin Morey <kevin@redhat.com>

  Description: This method pulls back a list of OpenStack VMs and passes
               the name

  Mandatory dialog fields: none
  Optional dialog fields: none
-------------------------------------------------------------------------------
   Copyright 2016 Kevin Morey <kevin@redhat.com>

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

def get_fog_object(type='Compute', tenant='admin', endpoint='publicURL')
  require 'fog'
  (@provider.api_version == 'v2') ? (conn_ref = '/v2.0/tokens') : (conn_ref = '/v3/auth/tokens')
  (@provider.security_protocol == 'non-ssl') ? (proto = 'http') : (proto = 'https')
  
  connection_hash = {
    :provider => 'OpenStack',
    :openstack_api_key => @provider.authentication_password,
    :openstack_username => @provider.authentication_userid,
    :openstack_auth_url => "#{proto}://#{@provider.hostname}:#{@provider.port}#{conn_ref}",
    :openstack_endpoint_type => endpoint,
    :openstack_tenant => tenant,
  }
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

begin
  dump_root()

  # initializing a couple of hashes
  # dialog_hash is what actually contains the contents of the dynamic dropdown
  dialog_hash = {}
  options_hash = {}

  # gathering some basic variables for use here and there
  provider_id =  $evm.root['dialog_provider_id'] || options_hash['provider_id']
  @provider = get_provider(provider_id)
  log_and_update_message(:info, "provider: #{@provider.name} provider id: #{@provider.id}")

  openstack_neutron = get_fog_object('Network')
  ext_net_list = openstack_neutron.list_networks.body["networks"].select do |net|
    net["router:external"] == true
  end
  ext_net_list.each do |net|
    dialog_hash[net["id"]] = "#{net["name"]} in #{@provider.name}"
  end

  if dialog_hash.blank?
    dialog_hash[''] = "< No External Nets found. Contact Admin >"
  else
    $evm.object['default_value'] = dialog_hash.first[0]
  end

  $evm.object['values'] = dialog_hash
  log_and_update_message(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")
end



