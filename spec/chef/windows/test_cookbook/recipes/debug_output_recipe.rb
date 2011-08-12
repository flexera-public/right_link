test_cookbook_echo 'recipe 1' do
  action :echo_debug
  message "debug message"
end

test_cookbook_echo 'recipe 2' do
  action :echo_verbose
  message "verbose message"
end
