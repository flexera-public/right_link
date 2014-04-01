class Chef

  module Formatters
    # == RightScriptFormatter
    # RightScale implememtation for Chef::Formatters::NullFormatter
    class RightScriptFormatter < Base

      cli_name(:right_script)

      def initialize(out, err)
        # the base class initialize method always creates a real outputter for
        # the given out,err pair, which results in printing to STDOUT,STDERR.
        # that seems like odd behavior for a null formatter that is documented
        # above as "doesn't actually produce any ouput" so let's not invoke the
        # base class here.
        #
        # puts is sometimes called on formatter.output so make the null
        # formatter refer to itself to defeat output.
        @output = self
      end

      def puts(*args)
        # do nothing
      end

      def print(*args)
        # do nothing
      end

      # Suprress description loging, because it contains useless information
      def resource_failed(resource, action, exception)
      end

    end
  end
end