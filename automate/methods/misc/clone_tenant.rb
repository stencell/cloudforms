=begin
  list_openstack_attached_volumes_ids.rb

  Author: Nate Stephany <nate@redhat.com>

  Description: This method lists all attached Cinder volumes for a vm
-------------------------------------------------------------------------------
   Copyright 2016 Nate Stephany <nate@redhat.com>

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

def create_new_tenant(source_tenant, new_tenant)
  openstack_keystone = get_fog_object('Identity')
  tenant = openstack_keystone.create_tenant(
    {
      :description => "Tenant cloned from #{source_tenant.name} on #{Time.now}",
      :enabled => true,
      :name => new_tenant
    }
  )
  return tenant
end

def list_tenant_nets(tenant)
  openstack_neutron = get_fog_object('Network', tenant)
  return = openstack_neutron.list_networks.body["networks"]
end

def clone_tenant_nets(tenant, net_list)
  openstack_neutron = get_fog_object('Network', tenant)

  unless net_list.blank?
    net_list.each do |net|
      net_name = net["name"]
      subnet = openstack_neutron.get_subnet(net["subnets"].first.body)
      subnet_name = subnet["subnet"]["name"]
      subnet_cidr = subnet["subnet"]["cidr"]

      openstack_neutron.create_network(
        {
          :name => net_name,
          :subnet_name => subnet_name,
          :subnet_cidr => subnet_cidr
        }
      )
    end
  end
end

def list_security_groups(tenant)
  openstack_nova = get_fog_object('Compute', tenant)
  return = openstack_nova.list_security_groups.body["security_groups"]
  # this gives back an array
end

def clone_security_groups(security_groups, tenant)
  openstack_nova = get_fog_object('Compute', tenant)

  unless security_groups.blank?
    security_groups.each do |sg|
      openstack_nova.create_security_group()

end

def clone_volumes()
  #use snapshots if volumes don't work
end

def clone_vm()
end

@provider = get_provider #need to add this method



source_tenant = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager_CloudTenant).find_by_id(dialog_source_tenant)
new_tenant = create_new_tenant(source_tenant, $evm.root('dialog_new_tenant'))

private_net_list = list_tenant_nets(source_tenant)
log(:info, "The network list to be cloned is #{private_net_list.inspect}")
clone_tenant_nets(new_tenant, private_net_list)

security_groups = list_security_groups(source_tenant)
clone_security_groups(security_groups, new_tenant)
