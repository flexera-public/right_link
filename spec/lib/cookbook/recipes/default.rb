ruby 'test_cookbook' do
  val = @node[:test_input]
  Chef::Log.info("Test input: #{val}")
  code 'puts "dummy"'
end
