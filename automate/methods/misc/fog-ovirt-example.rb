require 'fog'
# might require rbovirt, but don't need to require

connection_hash = {:ovirt_password=>"Redhat1!", :ovirt_username=>"admin@internal", :ovirt_url=>"https://10.11.164.20/api", :connection_options=>{:ssl_verify_peer=>false, :ssl_version=>:TLSv1}, :ovirt_ca_no_verify=>true}

conn = Fog::Compute::Ovirt.new(connection_hash)

conn.datacenters