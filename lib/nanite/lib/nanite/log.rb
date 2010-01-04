require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'agents', 'lib', 'common', 'right_link_log'))

module Nanite
  class Log < RightScale::RightLinkLog
  end
end
