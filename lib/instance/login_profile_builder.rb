module RightScale
  class LoginProfileBuilder
    attr_reader :username, :custom_data

    def initialize(username, custom_data)
      @username    = username
      @custom_data = custom_data
    end

    protected

    def home_directory

    end
  end
end