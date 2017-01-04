def log(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def get_aws_client(type='EC2')
  require 'aws-sdk'
  AWS.config(
    :access_key_id => @provider.authentication_userid,
    :secret_access_key => @provider.authentication_password,
    :region => @provider.provider_region
  )
  return Object::const_get("AWS").const_get("#{type}").new().client
end

@vm = $evm.root('vm')
@provider = $evm.vmdb('ManageIQ_Providers_Amazon_CloudManager').find_by_id(@vm.ems_id)

# populate this or pull from instance with $evm.object
sg_id = $evm.vmdb('ManageIQ_Providers_Amazon_NetworkManager_SecurityGroup').find_by_id($evm.root['dialog_sg_id']).ems_ref
log(:info, "Working with EC2 instance #{@vm.name} to assign security group #{sg_id}")

#did not test the get_aws_client method...assuming it works
ec2 = get_aws_client

existing_sg = ec2.describe_instance_attribute({instance_id: @vm.uid_ems, attribute: 'groupSet'}).to_h[:groups]
log(:info, "EC2 instance #{@vm.ref} currently has security groups #{existing_sg} assigned")

sg_array = []
existing_sg.each { |sg| sg_array.push(sg[:group_id]) }
sg_array.push(sg_id)
ec2.modify_instance_attribute({instance_id: @vm.uid_ems, groups: sg_array})
new_sg = ec2.describe_instance_attribute({instance_id: @vm.uid_ems, attribute: 'groupSet'}).to_h
log(:info, "EC2 instance #{new_sg[:instance_id]} has security groups #{new_sg[:groups]} assigned")