test_cookbook_encode 'recipe 1' do
  action :url_encode
  message "encode first"
end

powershell 'echo_from_powershell_script' do
  source_text = 'write-output "message from powershell script"'
  source source_text
end

test_cookbook_encode 'recipe 2' do
  action :update_chef_node
  message "encode again"
end

test_cookbook_echo 'recipe 3' do
  action :echo_text
  message "then echo"
end

test_cookbook_echo 'recipe 4' do
  action :check_chef_node
  # must be the same message as in the last encode::action :update_chef_node
  message "encode again"
end

powershell 'echo_from_powershell_script_again' do
  source_text = 'write-output "another powershell message"'
  source source_text
end

powershell 'echo_from_powershell_script_once_more' do
  source_text = 'write-output "one more powershell message"'
  source source_text
end

test_cookbook_echo 'recipe 5' do
  action :echo_text
  message "echo again"
end
