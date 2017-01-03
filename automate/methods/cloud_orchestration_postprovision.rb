#
# Description: This method examines the orchestration stack provisioned
#
def log(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def dump_stack_outputs(stack)
  log(:info, "Outputs from stack #{stack.name}")
  stack.outputs.each do |output|
    unless output.value.blank?
      @service.custom_set(output.key, output.value.to_s)
      @request.set_option(output.key, output.value)
      log(:info, "Key #{output.key}, value #{output.value}")
    end
  end
end

begin
  $evm.log("info", "Starting Orchestration Post-Provisioning")

  @request = $evm.root["service_template_provision_task"].miq_request
  @service = $evm.root["service_template_provision_task"].destination
  stack = @service.orchestration_stack

  dump_stack_outputs(stack)

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  $evm.root['ae_result'] = retry
  $evm.root['ae_retry_interval = 2.minutes']
  exit MIQ_OK
end
