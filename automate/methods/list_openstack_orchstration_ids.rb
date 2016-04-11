=begin
  list_openstack_vm_uids.rb

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
def log(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def dump_root()
  log(:info, "Begin $evm.root.attributes")
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}
  log(:info, "End $evm.root.attributes")
  log(:info, "")
end

def get_provider(provider_id=nil)
  if provider_id.blank?
    $evm.root.attributes.detect { |k,v| provider_id = v if k.end_with?('provider_id') } rescue nil
  end
  provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).find_by_id(provider_id)
  if provider.nil?
    provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).first
    log(:info, "Found provider: #{provider.name} via default method") if provider
  else
    log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}") if provider
  end
  provider ? (return provider) : (return nil)
end

def get_user
  user_search = $evm.root['dialog_userid'] || $evm.root['dialog_evm_owner_id']
  user = $evm.vmdb('user').find_by_id(user_search) ||
    $evm.vmdb('user').find_by_userid(user_search) ||
    $evm.root['user']
  user
end

def get_current_group_rbac_array
  rbac_array = []
  unless @user.current_group.filters.blank?
    @user.current_group.filters['managed'].flatten.each do |filter|
      next unless /(?<category>\w*)\/(?<tag>\w*)$/i =~ filter
      rbac_array << {category=>tag}
    end
  end
  log(:info, "rbac filters: #{rbac_array}")
  rbac_array
end

def object_eligible?(obj)
  @rbac_array.each do |rbac_hash|
    rbac_hash.each do |rbac_category, rbac_tags|
      Array.wrap(rbac_tags).each {|rbac_tag_entry| return false unless obj.tagged_with?(rbac_category, rbac_tag_entry) }
    end
    true
  end
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
  log(:info, "provider: #{@provider.name} provider id: #{@provider.id}")

  heat_template_list = $evm.vmdb(:orchestration_template).all.select { |t| t.type == "OrchestrationTemplateHot" }
  heat_template_list.each do |t|
    next if t.name.starts_with?("overcloud")
    next unless object_eligible?(t)
    dialog_hash[t.id] = "#{t.name}"
  end

  if dialog_hash.blank?
    dialog_hash[''] = "< no heat templates found >"
  else
    dialog_hash[''] = "< choose a template >"
  end

  $evm.object['values'] = dialog_hash
  log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")
end
