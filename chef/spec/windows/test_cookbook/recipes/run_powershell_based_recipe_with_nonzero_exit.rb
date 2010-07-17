test_cookbook_powershell_encode do
  action :url_encode
  message "encode first"
end

test_cookbook_powershell_encode do
  action :fail_with_nonzero_exit
  message "encode exit nonzero"
end

test_cookbook_powershell_encode do
  action :url_encode
  message "encode after fail"
end

test_cookbook_powershell_echo do
  action :echo_text
  message "echo again"
end
