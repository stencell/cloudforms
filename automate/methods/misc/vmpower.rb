#
#	Change Power State of a VM Method
#
$evm.log("info", "*****BEGIN POWER OPERATION FOR VM*****")

vm = $evm.root['vm'] || $evm.object['vm'] || $evm.vmdb('vm').find_by_name($evm.root['vm_name'])

unless vm.nil?
	if $evm.object['power_action'] == 'vmOff' && vm.power_state == 'on'
    $evm.log("info", "Shutting down VM: #{vm}")
    vm.stop
  elsif $evm.object['power_action'] == 'vmOn' && vm.power_state == 'off'
  	$evm.log("info", "Powering on VM: #{vm}")
  	vm.start
  else
  	$evm.log("info", "*****State & Instruction not compatible - Exiting*****")
  	exit MIQ_OK
  end
end

$evm.log("info", "*****FINISH POWER OFF VM*****")
exit MIQ_OK
