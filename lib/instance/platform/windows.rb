module RightScale
  # Windows specific implementation
  class Platform
    class Filesystem
      # Dynamic, persistent runtime state that is specific to RightLink
      def right_link_dynamic_state_dir
        return pretty_path(File.join(Dir::COMMON_APPDATA, 'RightScale', 'right_link'))
      end

      def right_link_home_dir
        unless @right_link_home_dir
          @right_link_home_dir = ENV['RS_RIGHT_LINK_HOME'] ||
                                 File.normalize_path(File.join(company_program_files_dir, 'RightLink'))
        end
        @right_link_home_dir
      end

      # Path to right link configuration and internal usage scripts
      def private_bin_dir
        return pretty_path(File.join(right_link_home_dir, 'bin'))
      end

      def sandbox_dir
        return pretty_path(File.join(right_link_home_dir, 'sandbox'))
      end
    end
  end
end
