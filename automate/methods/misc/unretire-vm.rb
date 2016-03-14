#
#	Unretire a VM Method
#
$evm.log("info", "*****BEGIN UNRETIRE VM*****")

vm = $evm.root['vm'] || $evm.object['vm'] || $evm.vmdb('vm').find_by_name($evm.root['vm_name'])
unless vm.nil?
    if vm.retired
      vm.retires_on = nil
      vm.retirement_state = nil
      $evm.log("info", "******Unretiring vm:#{vm.name}******")
      #vm.start
    else
    	$evm.log("info", "******VM is not retired...what are you thinking???????")
    	exit MIQ_OK
    end
end

$evm.log("info", "*****FINISH UNRETIRE VM*****")
exit MIQ_OK
