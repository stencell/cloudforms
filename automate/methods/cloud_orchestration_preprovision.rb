#
# Description: This method prepares arguments and parameters for orchestration provisioning
#
def log(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

$evm.log("info", "Starting Orchestration Pre-Provisioning")

service = $evm.root["service_template_provision_task"].destination

# Through service you can examine the orchestration template, manager (i.e., provider)
# stack_name, and options to create the stack
# You can also override these selections through service

$evm.log("info", "manager = #{service.orchestration_manager.name}(#{service.orchestration_manager.id})")
$evm.log("info", "template = #{service.orchestration_template.name}(#{service.orchestration_template.id}))")
$evm.log("info", "stack name = #{service.stack_name}")
# Caution: stack_options may contain passwords.
# $evm.log("info", "stack options = #{service.stack_options.inspect}")

# Example how to programmatically modify stack options:
# service.stack_name = 'new_name'
stack_options = service.stack_options
# stack_options[:disable_rollback] = false
# stack_options[:timeout_mins] = 2 # this option is provider dependent
# stack_options[:parameters]['flavor'] = 'm1.small'

$evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}
nested_templates = {}
log(:info, "created empty hash for #{nested_templates.inspect}")
template_regex = /dialog_nested_template\w/

$evm.root.attributes.each { |k,v| nested_templates[k] = ($evm.vmdb(:orchestration_template).all.detect \
                                                         { |t| t.id == v.to_i }.content) if k.to_s =~ template_regex }
log(:info, "populated nested_templates hash with values: #{nested_templates.inspect}")
nested_templates.clone.each { |k,v| nested_templates[k.sub(/dialog_nested_template_/, '')] = nested_templates.delete(k) }
log(:info, "stripped prefixes from keys in nested_templates: #{nested_templates.inspect}")
nested_templates.clone.each { |k,v| nested_templates[k.sub(/$/, '.yaml')] = nested_templates.delete(k) }
log(:info, "appended .yaml to nested template name to make it all work: #{nested_templates.inspect}")

stack_options[:files] = nested_templates
# # Important: set stack_options
service.stack_options = stack_options
