RIGHT_LINK_PATH = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'instance', 'right_link'))
path = File.join(RIGHT_LINK_PATH, 'agents', 'instance', 'instance.rb')
instance_eval(File.read(path), path)
register Tester.new
