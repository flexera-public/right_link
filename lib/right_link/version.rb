module RightLink
  module_function

  def version
    Gem.loaded_specs['right_link'].version.to_s
  end
end

