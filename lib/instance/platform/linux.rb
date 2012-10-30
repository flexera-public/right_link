module RightScale
  # Linux specific implementation
  class Platform
    class Filesystem
      # Dynamic, persistent runtime state that is specific to RightLink
      def right_link_dynamic_state_dir
        '/var/lib/rightscale/right_link'
      end

      # Path to right link configuration and internal usage scripts
      def private_bin_dir
        '/opt/rightscale/bin'
      end

      def sandbox_dir
        '/opt/rightscale/sandbox'
      end
    end
  end
end
