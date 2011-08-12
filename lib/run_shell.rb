module RunShell

  # Runs a shell command and pipes output to console.
  def runshell(cmd, ignoreerrors=false)
    puts "+ #{cmd}"
    IO.popen("#{cmd} 2>&1", 'r') do |output|
      output.sync = true
      done = false
      while !done
        begin
          puts output.readline
        rescue EOFError
          done = true
        end
      end
    end

    exitstatus = $?.exitstatus
    fail "SHELL COMMAND FAILED - exit code #{exitstatus}" unless (ignoreerrors || $?.success?)
    return exitstatus
  end

  # for Windows-specific tasks.
  def is_windows?
    return !!(RUBY_PLATFORM =~ /mswin/)
  end

end
