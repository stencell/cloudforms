#
# Run with powerOp.rb <vm name> <vmOn | vmOff>
#
require 'rest-client'
require 'json'

#Hack to disable SSL verification
require 'openssl'
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

@user_id = "admin"
@password = "..."
server_url = "something.something.something"
server_name = ARGV[0]
power_op = ARGV[1]

power_url = "https://#{server_url}/api/automation_requests"

resource = RestClient::Resource.new(power_url, @user_id, @password)
payload = 
                        {
                            "action" => "create",
                            "resource" => {
                                "version" => "1.1",
                                "uri_parts" => {
                                    "namespace" => "System",
                                    "class" => "Request",
                                    "instance" => "vmPower",
                                    "message" => "create"
                                },
                                "parameters" => {
                                    :vm_name => server_name,
                                    :powerState => power_op
                                },
                                "requester" => {
                                    "user_name" => "admin",
                                    "auto_approve" => true
                                }
                            }
                        }
response = resource.post(payload.to_json, "Content-Type" => "application/json")
