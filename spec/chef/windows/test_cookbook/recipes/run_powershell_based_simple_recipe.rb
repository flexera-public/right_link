test_cookbook_simple_encode 'recipe 1' do
  action :url_encode
end

test_cookbook_simple_echo 'recipe 2' do
  action :echo_text
end

test_cookbook_simple_encode 'recipe 3' do
  action :url_encode
end

test_cookbook_simple_echo 'recipe 4' do
  action :echo_text
end
