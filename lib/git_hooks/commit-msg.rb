#!/usr/bin/env ruby

# Disallow 'refs #' in right_link commits
if IO.read(ARGV[0]) =~ /^(refs #|Refs #)\d+ /
  puts 'Private ticket number reference.'
  exit 1
end
