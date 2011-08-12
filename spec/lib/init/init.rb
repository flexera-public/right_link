path = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'init', 'init.rb'))
instance_eval(File.read(path), path)
register Tester.new
