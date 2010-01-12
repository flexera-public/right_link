module RightScale

  COMMON_DEFAULT_OPTIONS = {
    :pass => 'testing',
    :vhost => '/nanite',
    :secure => false,
    :host => '0.0.0.0',
    :log_level => :info,
    :format => :marshal,
    :daemonize => false,
    :console => false,
    :root => Dir.pwd
  }

end
