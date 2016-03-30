require 'fog'

#note, you can run without :vsphere_expected_pubkey_hash and it should error and give you the value it was expecting
connection_hash = {:provider => "vsphere", :vsphere_username => "administrator@vsphere.local", :vsphere_password => "tahder1!", :vsphere_server => "10.11.164.10", :vsphere_expected_pubkey_hash => "454e19e2708ae733c9677fda2fe6958089bc58686860ccd97251f4650d392664"}

conn = Fog::Compute.new(connection_hash)