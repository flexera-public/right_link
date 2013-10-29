require 'rubygems'
require 'rubygems/package'

resource = ARGV.shift
out_file = ARGV.shift

FileUtils.mkdir_p(File.dirname(out_file))
Gem::Package::TarWriter.new(File.open(out_file, "w")) do |tar|
  tar.mkdir "cookbooks", 0644
  tar.add_file "resource", 0644 do |tf|
    tf.write resource
  end
end
