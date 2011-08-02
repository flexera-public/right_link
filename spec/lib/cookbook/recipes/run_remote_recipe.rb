if node[:trigger_remote_recipe] && node[:trigger_remote_recipe] != 'false'
  remote_recipe 'test_remote_recipe' do
    recipe 'test_cookbook::default'
    attributes({'test_input' => 'shazam!'})
    recipients node[:remote_recipe_recipient]
  end
end