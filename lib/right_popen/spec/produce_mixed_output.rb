count = ARGV[0] ? ARGV[0].to_i : 1

count.times do |i|
  $stderr.puts "stderr #{i}" if 0 == i % 10
  $stdout.puts "stdout #{i}"

  # throttle the producer because ruby stdio will deadlock processing realtime
  # data. the problem may be due to poor i/o synchronization in the
  # kernel when consuming both stderr and stdout.
  sleep 0.1 if 99 == i % 100
end

exit 99
