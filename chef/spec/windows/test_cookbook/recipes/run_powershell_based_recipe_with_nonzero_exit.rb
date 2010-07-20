test_cookbook_encode do
  action :url_encode
  message "encode first"
end

test_cookbook_encode do
  action :fail_with_nonzero_exit
  message "encode exit nonzero"
end

test_cookbook_encode do
  action :url_encode
  message "encode after fail"
end

test_cookbook_echo do
  action :echo_text
  message "echo again"
end
