test_cookbook_powershell_encode do
  action :url_encode
  message "encode first"
end

test_cookbook_powershell_echo do
  action :echo_text
  message "then echo"
end

test_cookbook_powershell_encode do
  action :fail_with_exception
  message "encode failed"
end

test_cookbook_powershell_encode do
  action :url_encode
  message "encode after fail"
end

test_cookbook_powershell_echo do
  action :echo_text
  message "echo again"
end