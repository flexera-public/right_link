test_cookbook_database "monkeynews" do
  type "innodb"
  action :create
  provider "test_cookbook_mysql"
end
