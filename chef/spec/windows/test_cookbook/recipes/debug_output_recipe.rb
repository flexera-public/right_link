test_cookbook_echo do
  action :echo_debug
  message "debug message"
end

test_cookbook_echo do
  action :echo_verbose
  message "verbose message"
end
