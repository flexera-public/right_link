test_cookbook_encode do
  action :url_encode
  message "encode this is a string with spaces"
end

test_cookbook_echo do
  action :echo_text
  message "echo this is a string with spaces"
end

test_cookbook_encode do
  action :url_encode
  message "SECOND STRING TO ENCODE"
end

test_cookbook_echo do
  action :echo_text
  message "SECOND STRING TO ECHO"
end
