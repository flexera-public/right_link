test_cookbook_encode 'recipe 1' do
  action :url_encode
  message "encode first"
end

test_cookbook_encode 'recipe 2' do
  action :fail_with_nonzero_exit
  message "encode exit nonzero"
end

test_cookbook_encode 'recipe 3' do
  action :url_encode
  message "encode after fail"
end

test_cookbook_echo 'recipe 4' do
  action :echo_text
  message "echo again"
end
