#
# Copyright (c) 2009-2011 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.join(File.dirname(__FILE__), 'spec_helper')

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
    @old_cache_path = RightScale::AgentConfig.cache_dir
    @temp_cache_path = File.join(File.dirname(__FILE__), 'test_cb')
    RightScale::AgentConfig.cache_dir = @temp_cache_path
    thread_name = RightScale::ExecutableBundle::DEFAULT_THREAD_NAME
    @cookbook = RightScale::RightScriptsCookbook.new(thread_name)
  end

  after(:each) do
    RightScale::AgentConfig.cache_dir = @old_cache_path
    FileUtils.rm_rf(@temp_cache_path)
  end

  it 'should create recipe instantiations' do
    recipe = @cookbook.recipe_from_right_script(@script)
    recipe.nickname.should =~ /^#{RightScale::RightScriptsCookbook::COOKBOOK_NAME}::/
    recipe.attributes.should == { @script.nickname => { "parameters" => @script.parameters } }
    recipe.id.should == 42
    recipe.ready.should be_true
  end

  it 'should persist recipes code' do
    recipe = @cookbook.recipe_from_right_script(@script)
    recipes_dir = @cookbook.instance_variable_get(:@recipes_dir)
    recipe_path = File.join(recipes_dir, recipe_from_script(@script.nickname, @cookbook))
    recipe_content = IO.read("#{recipe_path}.rb")
    regexp = "^right_script '#{@script.nickname}' do\n"
    regexp += "^  #{Regexp.escape("parameters(node[\"#{@script.nickname}\"][\"parameters\"])")}\n"
    regexp += "^  cache_dir +'#{Regexp.escape(@cookbook.cache_dir(@script))}'\n"
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
