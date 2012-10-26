module RightScale
  # Mac OS specific implementation
  class Platform
    class Filesystem
      # Static (time-invariant) state that is specific to RightLink
      def right_link_static_state_dir
        '/etc/rightscale.d/right_link'
      end

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
