require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'right_scripts_cookbook'
require 'instance_configuration'

describe RightScale::RightScriptsCookbook do

  before(:each) do
    # Note: source below shouldn't include regexp symbols for test to work
    @script = RightScale::RightScriptInstantiation.new(nickname='RightScript nickname',
                                      source="Some script with\nnew lines\nmore than one",
                                      parameters={ :first => 'one', :second => 'two' },
                                      attachments=[],
                                      packages=[],
                                      id=42,
                                      ready=true)
    @old_cache_path = RightScale::InstanceConfiguration::CACHE_PATH
    @temp_cache_path = File.join(File.dirname(__FILE__), 'test_cb')
    RightScale::InstanceConfiguration.const_set(:CACHE_PATH, @temp_cache_path)
    @cookbook = RightScale::RightScriptsCookbook.new(audit_id=1)
  end

  after(:each) do
    RightScale::InstanceConfiguration.const_set(:CACHE_PATH, @old_cache_path)
    FileUtils.rm_rf(@temp_cache_path)
  end

  it 'should create recipe instantiations' do
    recipe = @cookbook.recipe_from_right_script(@script)
    recipe.nickname.should =~ /^#{RightScale::RightScriptsCookbook::COOKBOOK_NAME}::/
    recipe.attributes.should be_nil
    recipe.id.should == 42
    recipe.ready.should be_true
  end

  it 'should persist recipes code' do
    recipe = @cookbook.recipe_from_right_script(@script)
    recipes_dir = @cookbook.instance_variable_get(:@recipes_dir)
    recipe_path = File.join(recipes_dir, recipe_from_script(@script.nickname, @cookbook))
    recipe_content = IO.read("#{recipe_path}.rb")
    regexp = "^right_script '#{@script.nickname}' do\n"
    regexp += "^  parameters\\(#{@script.parameters.inspect}\\)\n"
    regexp += "^  cache_dir +'#{@cookbook.cache_dir(@script)}'\n"
    regexp += "^  source_file +'#{recipe_path}'\n"
    regexp += "^end"
    recipe_content.should =~ /#{regexp}/
  end

  it 'should save the metadata' do
    recipe1 = @cookbook.recipe_from_right_script(@script)
    recipe2 = @cookbook.recipe_from_right_script(@script)
    recipe3 = @cookbook.recipe_from_right_script(@script)
    @cookbook.save
    cookbook_dir = @cookbook.instance_variable_get(:@cookbook_dir)
    metadata = IO.read(File.join(cookbook_dir, 'metadata.rb'))
    regexp = "^description \".+\"\n"
    regexp += "^recipe \"#{recipe1.nickname}\", \"RightScript < #{@script.nickname} >\"\n"
    regexp += "^recipe \"#{recipe2.nickname}\", \"RightScript < #{@script.nickname} >\"\n"
    regexp += "^recipe \"#{recipe3.nickname}\", \"RightScript < #{@script.nickname} >\"\n"
    metadata.should =~ /#{regexp}/
  end

  it 'should prevent adding new recipes after the metadata has been saved' do
    @cookbook.recipe_from_right_script(@script)
    @cookbook.save
    lambda { @cookbook.recipe_from_right_script(@script) }.should raise_error
  end

  # Retrieve recipe nickname from script nickname
  def recipe_from_script(script, cookbook)
    recipes = cookbook.instance_variable_get(:@recipes)
    recipes.invert[script]
  end

end