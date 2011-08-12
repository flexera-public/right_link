test_cookbook_encode 'recipe 1' do
  action :url_encode
  message "encode first"
end

test_cookbook_echo 'recipe 2' do
  action :echo_text
  message "then echo"
end

test_cookbook_encode 'recipe 3' do
  action :fail_with_explicit_throw
  message "encode failed"
end

test_cookbook_encode 'recipe 4' do
  action :url_encode
  message "encode after fail"
end

test_cookbook_echo 'recipe 5' do
  action :echo_text
  message "echo again"
end
