=begin
  keystone_delete_tenant.rb

  Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>,
          Nate Stephany <nate@redhat.com>

  Description: This method deletes an openstack tenant as a retirement state
               machine. Service must have at least the "tenant_name" custom
               attribute set.

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

def get_tenant()
  if @task
    ws_values = @task.options.fetch(:ws_values, {}) rescue {}
    cloud_tenant_search_criteria = @task.get_option(:cloud_tenant_id) || ws_values[:cloud_tenant_id] ||
      @task.get_option(:cloud_tenant) || ws_values[:cloud_tenant] || 'admin' rescue 'admin'
  else
    cloud_tenant_search_criteria = 'admin'
  end
  tenant = $evm.vmdb(:cloud_tenant).find_by_id(cloud_tenant_search_criteria) ||
    $evm.vmdb(:cloud_tenant).find_by_name(cloud_tenant_search_criteria) ||
    $evm.vmdb(:cloud_tenant).all.detect { |ct| ct.name.casecmp(cloud_tenant_search_criteria)==0 }
  return tenant
end

def clean_network(tenant_id)
  #defaulting to admin so we can see all network objects
  openstack_neutron = get_fog_object('Network')
  router_list = openstack_neutron.list_routers.body["routers"].select { |r| r["tenant_id"] == tenant_id }
  port_list = openstack_neutron.list_ports.body["ports"].select { |p| p["tenant_id"] == tenant_id }
  log_and_update_message(:info, "The router list for #{tenant_id} is #{router_list.inspect}")
  # as long as there are routers to delete, lets get to deleting
    unless router_list.nil?
    router_list.each { |router|
      log_and_update_message(:info, "Removing interfaces from router #{router["name"]}")
      # get the list of internal router interface ports
      router_internal_ports = port_list.select { |port| port["device_id"] == router["id"] &&
        port"device_owner"] == "network:router_interface" }
      # for each of the ports identified, remove them from the router
      router_internal_ports.each { |p| openstack_neutron.remove_router_interface(router["id"], p["fixed_ips"][0]["subnet_id"])}
      # remove the router once all the ports are gone
      log_and_update_message(:info, "Deleting router #{router["name"]} from tenant #{tenant_id}")
      openstack_neutron.delete_router(router["id"])
    }
    end
    # consider adding in security group cleanup as well
end

begin
  $evm.root.attributes.sort.each { |k, v| log_and_update_message(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'service'
    @service = $evm.root['service']
    log_and_update_message(:info, "Service: #{@service.name} id: #{@service.id}")
    @provider = get_provider(@service.custom_get("PROVIDER_ID")) ||
      get_provider
  else
    exit MIQ_OK
  end

  # tenant is used to connect to Openstack to process deletion. Typically falls to 'admin'
  tenant = get_tenant
  raise "no tenant found" if tenant.nil?
  log_and_update_message(:info, "provider: #{@provider.name} tenant: #{tenant.name}")

  # Service must have custom attributes set already since this is what we look for
  retired_tenant_id = @service.custom_get("tenant_id")
  retired_tenant_name = @service.custom_get("tenant_name")
  # look up the tenant ID based on the name in case ID wasn't set as an attribute when created
  unless retired_tenant_id
    retired_tenant_id = $evm.vmdb(:cloud_tenant).all.detect { |ct| ct.name == retired_tenant_name}["ems_ref"]
  end
  log_and_update_message(:info, "provider: #{@provider.name} retired_tenant_name: #{retired_tenant_name} retired_tenant_id: #{retired_tenant_id}")
  raise "no tenant found" if retired_tenant_id.nil?

  # Add network cleanup here before we process actual tenant delete
  clean_network(retired_tenant_id)

  openstack_keystone = get_fog_object('Identity', tenant.name)

  # send delete to OpenStack using the retired_tenant_id gathered earlier
  log_and_update_message(:info, "Deleting tenant #{retired_tenant_id} from OpenStack")
  response = openstack_keystone.delete_tenant(retired_tenant_id)
  log_and_update_message(:info, "Delete Response #{response.inspect}")

  log_and_update_message(:info, "Fully retiring service")
  @service.remove_from_vmdb
  @provider.refresh

rescue => err
  log_and_update_message(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end
