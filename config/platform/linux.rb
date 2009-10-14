#
# Copyright (c) 2009 RightScale Inc
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

module RightScale
  class Platform
    class Linux
      attr_reader :distro, :release, :codename

      #Initialize
      def initialize
        @distro  = `lsb_release -ds`
        @release =  `lsb_release -vs`
        @codename = `lsb_release -cs`
      end

      # Is this machine running Ubuntu?
      #
      # === Return
      # true:: If Linux distro is Ubuntu
      # false:: Otherwise
      def ubuntu?
        distro =~ /Ubuntu/i
      end

      # Is this machine running CentOS?
      #
      # === Return
      # true:: If Linux distro is CentOS
      # false:: Otherwise
      def centos?
        distro =~ /CentOS/i
      end

      class Filesystem
        def right_scale_state_dir
          '/etc/rightscale.d'
        end

        def spool_dir
          '/var/spool'
        end

        def cache_dir
          '/var/cache/rightscale'
        end
      end
    end
  end
end