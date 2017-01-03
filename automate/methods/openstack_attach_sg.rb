def log(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def get_fog_object(type='Compute', tenant='admin', endpoint='adminURL')
  require 'fog/openstack'
  (@provider.api_version == 'v2') ? (conn_ref = '/v2.0/tokens') : (conn_ref = '/v3/auth/tokens')
  (@provider.security_protocol == 'non-ssl') ? (proto = 'http') : (proto = 'https')

  connection_hash = {
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
  return Object::const_get("Fog").const_get("#{type}").const_get("OpenStack").new(connection_hash)
end

def attach_osp_sg(vm_id, sg_name, tenant)
  openstack_nova = get_fog_object('Compute', tenant_name)
  openstack_nova.add_security_group(vm_id, sg_name)
end

@vm = $evm.root('vm')
provider = @vm.ems_id
tenant = provider.cloud_tenants.detect { |t| t.id == @vm.cloud_tenant_id }
log(:info, "vm name: #{@vm.name}, provider: #{@provider.name}, tenant: #{tenant.name}")

# make this dynamic and pull from $evm.root/object
sg_name = 'new-sec-grp'

attach_osp_sg(@vm.id, sg_name, tenant.name)