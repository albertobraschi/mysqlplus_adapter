require "#{File.dirname(__FILE__)}/helper"
Mysqlplus::Test.prepare!

class DeferrableTest < Test::Unit::TestCase
  
  def test_should_be_able_to_find_records_in_a_background_thread
    assert_equal MysqlUser.find(:first, :defer => true), MysqlUser.find(:first) 
    assert_instance_of MysqlUser, MysqlUser.find(:first, :defer => true)
  end

  def test_should_be_able_to_find_records_by_sql_background_thread
    assert_equal MysqlUser.find_by_sql("SELECT * FROM mysql.user WHERE User = 'root'", true), MysqlUser.find(:all, :conditions => ['user.User = ?', 'root']) 
  end
    
end