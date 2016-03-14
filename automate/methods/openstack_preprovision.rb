=begin
  openstack_preprovision.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method is used to apply PreProvision customizations for
               Openstack provisioning

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
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}
  log_and_update_message(:info, "End $evm.root.attributes")
  log_and_update_message(:info, "")
end

def add_volumes(ws_values, template)
  # add created volumes and add them to the clone_options
  log_and_update_message(:info, "Processing add_volumes...", true)
  volume_hash = @task.options[:volume_hash]
  log_and_update_message(:info, "volume_hash: #{volume_hash.inspect}")

  unless volume_hash.blank?
    volume_array = []
    # pull out boot volume 0 hash for later processing
    boot_volume_size = volume_hash[0][:size].to_i rescue 0
    unless boot_volume_size.zero?
      # add extra volumes to volume_array
      volume_hash.each do |boot_index, volume_options|
        next if volume_options[:uuid].blank?
        (volume_options[:delete_on_termination] =~ (/(false|f|no|n|0)$/i)) ? (delete_on_termination = false) : (delete_on_termination = true)
        log_and_update_message(:info, "Processing boot_index: #{boot_index} - #{volume_options.inspect}")
        if boot_index.zero?
          boot_block_device = {
            :boot_index => boot_index,
            :source_type => 'volume',
            :destination_type => 'volume',
            :uuid => volume_options[:uuid],
            :delete_on_termination => delete_on_termination,
          }
          unless volume_options[:device_name] =~ (/(false|f|no|n|0)$/i)
            boot_block_device[:device_name] = volume_options[:device_name]
          end
          log_and_update_message(:info, "volume: #{boot_index} - boot_block_device: #{boot_block_device.inspect}")
          volume_array << boot_block_device
        else
          new_volume = { :boot_index => boot_index, :source_type => 'volume', :destination_type => 'volume', :uuid => volume_options[:uuid], :delete_on_termination => delete_on_termination }
          log_and_update_message(:info, "volume: #{boot_index} - new_volume: #{new_volume.inspect}")
          volume_array << new_volume
        end
      end
      unless volume_array.blank?
        clone_options = @task.get_option(:clone_options) || {}
        clone_options.merge!({ :image_ref => nil, :block_device_mapping_v2 => volume_array })
        @task.set_option(:clone_options, clone_options)
        log_and_update_message(:info, "Provisioning object updated {:clone_options => #{@task.options[:clone_options].inspect}}")
      end
    else
      log_and_update_message(:info, "Boot disk is ephemeral, skipping add_volumes as extra disks if any will be attached during post provisioning")
    end
  end
  log_and_update_message(:info, "Processing add_volumes...Complete", true)
end

def add_affinity_group(ws_values)
  # add affinity group id to clone options
  log_and_update_message(:info, "Processing add_affinity_group...", true)
  server_group_id = @task.get_option(:server_group_id) || ws_values[:server_group_id] rescue nil
  unless server_group_id.nil?
    clone_options = @task.get_option(:clone_options) || {}
    clone_options[:os_scheduler_hints] = { :group => "#{server_group_id}" }
    @task.set_option(:clone_options, clone_options)
    log_and_update_message(:info, "Provisioning object updated {:clone_options => #{@task.options[:clone_options].inspect}}")
  end
  log_and_update_message(:info, "Processing add_affinity_group...Complete", true)
end

def add_tenant(ws_values)
  # ensure that the tenant is set
  log_and_update_message(:info, "Processing add_tenant...", true)
  if @task.get_option(:cloud_tenant).blank?
    tenant_id   = @task.get_option(:cloud_tenant) || ws_values[:cloud_tenant] rescue nil
    tenant_id ||= @task.get_option(:cloud_tenant_id) || ws_values[:cloud_tenant_id] rescue nil
    unless tenant_id.nil?
      tenant = $evm.vmdb(:cloud_tenant).find_by_id(tenant_id)
      log_and_update_message(:info, "Using tenant: #{tenant.name} id: #{tenant.id} ems_ref: #{tenant.ems_ref}")
    else
      tenant = $evm.vmdb(:cloud_tenant).find_by_name('admin')
      log_and_update_message(:info, "Using default tenant: #{tenant.name} id: #{tenant.id} ems_ref: #{tenant.ems_ref}")
    end
    @task.set_option(:cloud_tenant, [tenant.id, tenant.name])
    log_and_update_message(:info, "Provisioning object updated {:cloud_tenant => #{@task.options[:cloud_tenant].inspect}}")
  end
  log_and_update_message(:info, "Processing add_tenant...Complete", true)
end

def add_networks(ws_values)
  # ensure the cloud_network is set and look for additional networks to add to clone_options
  log_and_update_message(:info, "Processing add_networks...", true)
  clone_options = @task.get_option(:clone_options) || {}
  clone_options[:nics] = []
  cloud_network_id = @task.get_option(:cloud_network_0) || ws_values[:cloud_network_0] rescue nil
  cloud_network_id ||= @task.get_option(:cloud_network) || ws_values[:cloud_network] rescue nil
  n = 0
  while !cloud_network_id.nil? do
    log_and_update_message(:info, "cloud network id found: #{cloud_network_id}", true)
    cloud_network = $evm.vmdb(:cloud_network).find_by_id(cloud_network_id)
    break if cloud_network.nil?
    log_and_update_message(:info, "cloud network object found: #{cloud_network.inspect}", true)
    clone_options[:nics][n] = {}
    clone_options[:nics][n]['net_id'] = cloud_network['ems_ref'].to_s
    n +=1
    cloud_network_id = nil
    cloud_network_id ||= @task.get_option("cloud_network_#{n}".to_sym) || ws_values["cloud_network_#{n}".to_sym] rescue nil
  end
  log_and_update_message(:info, "Clone options updated with NIC information: #{clone_options.inspect}", true)
  @task.set_option(:clone_options, clone_options)
  log_and_update_message(:info, "Processing add_networks...Complete", true)
end

###############
# Start Method
###############
begin
  log_and_update_message(:info, "CloudForms Automate Method Started", true)
  dump_root()

  # Get provisioning object
  @task     = $evm.root['miq_provision']
  log_and_update_message(:info, "Provisioning ID:<#{@task.id}> Provision Request ID:<#{@task.miq_provision_request.id}> Provision Type: <#{@task.provision_type}>")

  template  = @task.vm_template

  # Gets the ws_values
  ws_values = @task.options.fetch(:ws_values, {})

  add_tenant(ws_values)

  add_volumes(ws_values, template)

  add_affinity_group(ws_values)

  add_networks(ws_values)

  # Log all of the options to the automation.log
  @task.options.each { |k,v| log_and_update_message(:info, "Provisioning Option Key(#{k.class}): #{k.inspect} Value: #{v.inspect}") }

  ###############
  # Exit Method
  ###############
  log_and_update_message(:info, "CloudForms Automate Method Ended", true)
  exit MIQ_OK

  # Set Ruby rescue behavior
rescue => err
  log_and_update_message(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  @task.finished("#{err}") if @task && @task.respond_to?('finished')
  exit MIQ_ABORT
end
