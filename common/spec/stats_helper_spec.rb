#
# Copyright (c) 2009 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.join(File.dirname(__FILE__), 'spec_helper')

describe RightScale::StatsHelper do

  include FlexMock::ArgumentTypes

  describe "ActivityStats" do

    before(:each) do
      @now = 1000000
      flexmock(Time).should_receive(:now).and_return(@now).by_default
      @stats = RightScale::StatsHelper::ActivityStats.new
    end

    it "should initialize stats data" do
      @stats.instance_variable_get(:@interval).should == 0.0
      @stats.instance_variable_get(:@last_start_time).should == @now
      @stats.instance_variable_get(:@avg_duration).should == 0.0
      @stats.instance_variable_get(:@total).should == 0
      @stats.instance_variable_get(:@count_per_type).should == {}
    end

    it "should update count and interval information" do
      flexmock(Time).should_receive(:now).and_return(1000010)
      @stats.update
      @stats.instance_variable_get(:@interval).should == 1.0
      @stats.instance_variable_get(:@last_start_time).should == @now + 10
      @stats.instance_variable_get(:@avg_duration).should == 0.0
      @stats.instance_variable_get(:@total).should == 1
      @stats.instance_variable_get(:@count_per_type).should == {}
    end

    it "should update weight the average interval toward recent activity" do
    end

    it "should update counts per type when type provided" do
      flexmock(Time).should_receive(:now).and_return(1000010)
      @stats.update("test")
      @stats.instance_variable_get(:@interval).should == 1.0
      @stats.instance_variable_get(:@last_start_time).should == @now + 10
      @stats.instance_variable_get(:@avg_duration).should == 0.0
      @stats.instance_variable_get(:@total).should == 1
      @stats.instance_variable_get(:@count_per_type).should == {"test" => 1}
    end

    it "should not update counts when type contains 'stats'" do
      flexmock(Time).should_receive(:now).and_return(1000010)
      @stats.update("my stats")
      @stats.instance_variable_get(:@interval).should == 0.0
      @stats.instance_variable_get(:@last_start_time).should == @now
      @stats.instance_variable_get(:@avg_duration).should == 0.0
      @stats.instance_variable_get(:@total).should == 0
      @stats.instance_variable_get(:@count_per_type).should == {}
    end

    it "should not measure rate if disabled" do
      @stats = RightScale::StatsHelper::ActivityStats.new(false)
      flexmock(Time).should_receive(:now).and_return(1000010)
      @stats.update
      @stats.instance_variable_get(:@interval).should == 0.0
      @stats.instance_variable_get(:@last_start_time).should == @now + 10
      @stats.instance_variable_get(:@avg_duration).should == 0.0
      @stats.instance_variable_get(:@total).should == 1
      @stats.instance_variable_get(:@count_per_type).should == {}
    end

    it "should update duration when finish using internal start time by default" do
      flexmock(Time).should_receive(:now).and_return(1000010)
      @stats.finish
      @stats.instance_variable_get(:@interval).should == 0.0
      @stats.instance_variable_get(:@last_start_time).should == @now
      @stats.instance_variable_get(:@avg_duration).should == 1.0
      @stats.instance_variable_get(:@total).should == 0
      @stats.instance_variable_get(:@count_per_type).should == {}
    end

    it "should update duration when finish using specified start time" do
      flexmock(Time).should_receive(:now).and_return(1000030)
      @stats.avg_duration.should be_nil
      @stats.finish(1000010)
      @stats.instance_variable_get(:@interval).should == 0.0
      @stats.instance_variable_get(:@last_start_time).should == @now
      @stats.instance_variable_get(:@avg_duration).should == 2.0
      @stats.instance_variable_get(:@total).should == 0
      @stats.instance_variable_get(:@count_per_type).should == {}
    end

    it "should convert interval to rate" do
      flexmock(Time).should_receive(:now).and_return(1000020)
      @stats.avg_rate.should be_nil
      @stats.update
      @stats.instance_variable_get(:@interval).should == 2.0
      @stats.avg_rate.should == 0.5
    end

    it "should report number of seconds since last update or nil if no updates" do
      flexmock(Time).should_receive(:now).and_return(1000010)
      @stats.last.should be_nil
      @stats.update
      @stats.last.should == {"elapsed" => 0}
    end

    it "should report number of seconds since last update and last type" do
      @stats.update("test")
      flexmock(Time).should_receive(:now).and_return(1000010)
      @stats.last.should == {"elapsed" => 10, "type" => "test"}
    end

    it "should report whether last action is still active" do
      @stats.update("test", "token")
      flexmock(Time).should_receive(:now).and_return(1000010)
      @stats.last.should == {"elapsed" => 10, "type" => "test", "active" => true}
      @stats.finish(@now - 10, "token")
      @stats.last.should == {"elapsed" => 10, "type" => "test", "active" => false}
      @stats.instance_variable_get(:@avg_duration).should == 2.0
    end

    it "should convert count per type to percentages" do
      flexmock(Time).should_receive(:now).and_return(1000010)
      @stats.update("foo")
      @stats.instance_variable_get(:@total).should == 1
      @stats.instance_variable_get(:@count_per_type).should == {"foo" => 1}
      @stats.percentage.should == {"total" => 1, "percent" => {"foo" => 100.0}}
      @stats.update("bar")
      @stats.instance_variable_get(:@total).should == 2
      @stats.instance_variable_get(:@count_per_type).should == {"foo" => 1, "bar" => 1}
      @stats.percentage.should == {"total" => 2, "percent" => {"foo" => 50.0, "bar" => 50.0}}
      @stats.update("foo")
      @stats.update("foo")
      @stats.instance_variable_get(:@total).should == 4
      @stats.instance_variable_get(:@count_per_type).should == {"foo" => 3, "bar" => 1}
      @stats.percentage.should == {"total" => 4, "percent" => {"foo" => 75.0, "bar" => 25.0}}
    end

  end # ActivityStats

  describe "ExceptionStats" do

    before(:each) do
      @now = 1000000
      flexmock(Time).should_receive(:now).and_return(@now).by_default
      @stats = RightScale::StatsHelper::ExceptionStats.new
      @exception = Exception.new("Test error")
    end

    it "should initialize stats data" do
      @stats.stats.should == {}
      @stats.instance_variable_get(:@callback).should be_nil
    end

    it "should track submitted exception information by category" do
      @stats.track("testing", @exception)
      @stats.stats.should == {"testing" => {"total" => 1,
                                            "recent" => [{"count" => 1, "type" => "Exception", "message" => "Test error",
                                                          "when" => @now, "where" => nil}]}}
    end

    it "should recognize and count repeated exceptions" do
      @stats.track("testing", @exception)
      @stats.stats.should == {"testing" => {"total" => 1,
                                            "recent" => [{"count" => 1, "type" => "Exception", "message" => "Test error",
                                                          "when" => @now, "where" => nil}]}}
      flexmock(Time).should_receive(:now).and_return(1000010)
      category = "another"
      backtrace = ["here", "and", "there"]
      4.times do |i|
        begin
          raise ArgumentError, "badarg"
        rescue Exception => e
          flexmock(e).should_receive(:backtrace).and_return(backtrace)
          @stats.track(category, e)
          backtrace.shift(2) if i == 1
          category = "testing" if i == 2
        end
      end
      @stats.stats.should == {"testing" => {"total" => 2,
                                            "recent" => [{"count" => 1, "type" => "Exception", "message" => "Test error",
                                                          "when" => @now, "where" => nil},
                                                         {"count" => 1, "type" => "ArgumentError", "message" => "badarg",
                                                          "when" => @now + 10, "where" => "there"}]},
                              "another" => {"total" => 3,
                                            "recent" => [{"count" => 2, "type" => "ArgumentError", "message" => "badarg",
                                                          "when" => @now + 10, "where" => "here"},
                                                         {"count" => 1, "type" => "ArgumentError", "message" => "badarg",
                                                          "when" => @now + 10, "where" => "there"}]}}
    end

    it "should limit the number of exceptions stored by eliminating older exceptions" do
      (RightScale::StatsHelper::ExceptionStats::MAX_RECENT_EXCEPTIONS + 1).times do |i|
        begin
          raise ArgumentError, "badarg"
        rescue Exception => e
          flexmock(e).should_receive(:backtrace).and_return([i.to_s])
          @stats.track("testing", e)
        end
      end
      stats = @stats.stats
      stats["testing"]["total"].should == RightScale::StatsHelper::ExceptionStats::MAX_RECENT_EXCEPTIONS + 1
      stats["testing"]["recent"].size.should == RightScale::StatsHelper::ExceptionStats::MAX_RECENT_EXCEPTIONS
      stats["testing"]["recent"][0]["where"].should == "1"
    end

    it "should make callback if callback and message defined" do
      called = 0
      callback = lambda do |exception, message, server|
        called += 1
        exception.should == @exception
        message.should == "message"
        server.should == "server"
      end
      @stats = RightScale::StatsHelper::ExceptionStats.new("server", callback)
      @stats.track("testing", @exception, "message")
      @stats.stats.should == {"testing" => {"total" => 1,
                                            "recent" => [{"count" => 1, "type" => "Exception", "message" => "Test error",
                                                          "when" => @now, "where" => nil}]}}
      called.should == 1
    end

    it "should catch any exceptions raised internally" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to track exception/).once
      flexmock(@exception).should_receive(:backtrace).and_raise(Exception)
      @stats = RightScale::StatsHelper::ExceptionStats.new
      @stats.track("testing", @exception, "message")
      @stats.stats["testing"]["total"].should == 1
    end

  end # ExceptionStats

  describe "Formatting" do

    include RightScale::StatsHelper

    before(:each) do
      @now = 1000000
      flexmock(Time).should_receive(:now).and_return(@now).by_default
      @exceptions = RightScale::StatsHelper::ExceptionStats.new
      @brokers = {"brokers"=> [{"identity"=>"rs-broker-localhost-5672", "disconnects" => 0, "tries"=>0, "alias"=>"b0", "status"=>"connected"},
                               {"identity"=>"rs-broker-localhost-5673", "disconnects" => 1, "tries"=>0, "alias"=>"b1", "status"=>"disconnected"}],
                  "exceptions" => {}}
    end

    it "should convert values to percentages" do
      stats = {"first" => 1, "second" => 4, "third" => 3}
      result = percentage(stats)
      result.should == {"total" => 8, "percent" => {"first" => 12.5, "second" => 50.0, "third" => 37.5}}
    end

    it "should sort hash into array with integer conversion of keys if possible" do
      sort({"c" => 3, "a" => 1, "b" => 2}).should == [["a", 1], ["b", 2], ["c", 3]]
      sort({3 => "c", 1 => "a", 2 => "b"}).should == [[1, "a"], [2, "b"], [3, "c"]]
      sort({11 => "c", 9 => "a", 10 => "b"}).should == [[9, "a"], [10, "b"], [11, "c"]]
    end

    it "should wrap string by breaking it into lines at the specified separator" do
      string = "Now is the time for all good men to come to the aid of their people."
      result = wrap(string, 20, "    ", " ")
      result.should == "Now is the time for \n" +
                       "    all good men to come \n" +
                       "    to the aid of their \n" +
                       "    people."
      string = "dogs: 2, cats: 10, hippopotami: 99, bears: 1, ants: 100000"
      result = wrap(string, 22, "--", ", ")
      result.should == "dogs: 2, cats: 10, \n" +
                       "--hippopotami: 99, \n" +
                       "--bears: 1, ants: 100000"
    end

    it "should convert elapsed time to displayable format" do
      elapsed(0).should == "0 sec"
      elapsed(1).should == "1 sec"
      elapsed(60).should == "60 sec"
      elapsed(61).should == "1 min, 1 sec"
      elapsed(62).should == "1 min, 2 sec"
      elapsed(120).should == "2 min, 0 sec"
      elapsed(3600).should == "60 min, 0 sec"
      elapsed(3601).should == "1 hr, 0 min"
      elapsed(3659).should == "1 hr, 0 min"
      elapsed(3660).should == "1 hr, 1 min"
      elapsed(3720).should == "1 hr, 2 min"
      elapsed(7200).should == "2 hr, 0 min"
      elapsed(7260).should == "2 hr, 1 min"
      elapsed(86400).should == "24 hr, 0 min"
      elapsed(86401).should == "1 day, 0 hr, 0 min"
      elapsed(86459).should == "1 day, 0 hr, 0 min"
      elapsed(86460).should == "1 day, 0 hr, 1 min"
      elapsed(90000).should == "1 day, 1 hr, 0 min"
      elapsed(183546).should == "2 days, 2 hr, 59 min"
      elapsed(125.5).should == "2 min, 5 sec"
    end

    it "should convert floating point values to decimal digit string with at least two digit precision" do
      enough_precision(100.5).should == "101"
      enough_precision(100.4).should == "100"
      enough_precision(99.0).should == "99"
      enough_precision(10.5).should == "11"
      enough_precision(10.4).should == "10"
      enough_precision(9.15).should == "9.2"
      enough_precision(9.1).should == "9.1"
      enough_precision(1.05).should == "1.1"
      enough_precision(1.01).should == "1.0"
      enough_precision(1.0).should == "1.0"
      enough_precision(0.995).should == "1.00"
      enough_precision(0.991).should == "0.99"
      enough_precision(0.0995).should == "0.100"
      enough_precision(0.0991).should == "0.099"
      enough_precision(0.00995).should == "0.0100"
      enough_precision(0.00991).should == "0.0099"
      enough_precision(0.000995).should == "0.00100"
      enough_precision(0.000991).should == "0.00099"
      enough_precision(0.000005).should == "0.00001"
      enough_precision(0.000001).should == "0.00000"
      enough_precision(0.0).should == "0"
      enough_precision(55).should == "55"
      enough_precision({"a" => 65.0, "b" => 23.0, "c" => 12.0}).should == {"a" => "65", "b" => "23", "c" => "12"}
      enough_precision({"a" => 65.0, "b" => 33.0, "c" => 2.0}).should == {"a" => "65.0", "b" => "33.0", "c" => "2.0"}
      enough_precision({"a" => 10.45, "b" => 1.0, "c" => 0.011}).should == {"a" => "10.5", "b" => "1.0", "c" => "0.011"}
      enough_precision({"a" => 1000.0, "b" => 0.1, "c" => 0.0, "d" => 0.0001, "e" => 0.00001, "f" => 0.000001}).should ==
                       {"a" => "1000.0", "b" => "0.10", "c" => "0.0", "d" => "0.00010", "e" => "0.00001", "f" => "0.00000"}
    end

    it "should convert broker status to multi-line display string" do
      result = brokers_str(@brokers, 10)
      result.should == "brokers    : b0: rs-broker-localhost-5672, status: connected, disconnects: 0, tries: 0\n" +
                       "             b1: rs-broker-localhost-5673, status: disconnected, disconnects: 1, tries: 0\n" +
                       "             exceptions        : none\n"
    end

    it "should display broker exceptions" do
      @exceptions.track("testing", Exception.new("Test error"))
      @brokers["exceptions"] = @exceptions.stats
      result = brokers_str(@brokers, 10)
      result.should == "brokers    : b0: rs-broker-localhost-5672, status: connected, disconnects: 0, tries: 0\n" +
                       "             b1: rs-broker-localhost-5673, status: disconnected, disconnects: 1, tries: 0\n" +
                       "             exceptions        : testing total: 1, most recent:\n" +
                       "                                 (1) Mon Jan 12 05:46:40 -0800 1970 Exception: Test error\n" +
                       "                                     \n"
    end

    it "should convert exception stats to multi-line string" do
      @exceptions.track("testing", Exception.new("This is a very long exception message that should be truncated " +
                                                 "to a reasonable length"))
      flexmock(Time).should_receive(:now).and_return(1000010)
      category = "another"
      backtrace = ["It happened here", "Over there"]
      4.times do |i|
        begin
          raise ArgumentError, "badarg"
        rescue Exception => e
          flexmock(e).should_receive(:backtrace).and_return(backtrace)
          @exceptions.track(category, e)
          backtrace.shift(1) if i == 1
          category = "testing" if i == 2
        end
      end

      result = exceptions_str(@exceptions.stats, "----")
      result.should == "another total: 3, most recent:\n" +
                   "----(1) Mon Jan 12 05:46:50 -0800 1970 ArgumentError: badarg\n" +
                   "----    Over there\n" +
                   "----(2) Mon Jan 12 05:46:50 -0800 1970 ArgumentError: badarg\n" +
                   "----    It happened here\n" +
                   "----testing total: 2, most recent:\n" +
                   "----(1) Mon Jan 12 05:46:50 -0800 1970 ArgumentError: badarg\n" +
                   "----    Over there\n" +
                   "----(1) Mon Jan 12 05:46:40 -0800 1970 Exception: This is a very long exception message that should be truncate...\n" +
                   "----    "
    end

    it "should convert nested hash into string with keys sorted numerically if possible, else alphabetically" do
      hash = {"dogs" => 2, "cats" => 3, "hippopotami" => 99, "bears" => 1, "ants" => 100000000, "dragons" => nil,
              "food" => {"apples" => "bushels", "berries" => "lots", "meat" => {"fish" => 10.54, "beef" => nil}},
              "versions" => { "1" => 10, "5" => 50, "10" => 100} }
      result = hash_str(hash)
      result.should == "ants: 100000000, bears: 1, cats: 3, dogs: 2, dragons: none, " +
                       "food: [ apples: bushels, berries: lots, meat: [ beef: none, fish: 11 ] ], " +
                       "hippopotami: 99, versions: [ 1: 10, 5: 50, 10: 100 ]"
      result = wrap(result, 20, "----", ", ")
      result.should == "ants: 100000000, \n" +
                   "----bears: 1, cats: 3, \n" +
                   "----dogs: 2, \n" +
                   "----dragons: none, \n" +
                   "----food: [ apples: bushels, \n" +
                   "----berries: lots, \n" +
                   "----meat: [ beef: none, \n" +
                   "----fish: 11 ] ], \n" +
                   "----hippopotami: 99, \n" +
                   "----versions: [ 1: 10, \n" +
                   "----5: 50, 10: 100 ]"
    end

    it "should convert sub-stats to a display string" do
      @exceptions.track("testing", Exception.new("Test error"))
      activity1 = RightScale::StatsHelper::ActivityStats.new
      activity2 = RightScale::StatsHelper::ActivityStats.new
      activity3 = RightScale::StatsHelper::ActivityStats.new
      activity2.update("stats")
      activity2.update("testing")
      activity2.update("more testing")
      activity2.update("more testing")
      activity2.update("more testing")
      activity3.update("testing forever", "id")
      flexmock(Time).should_receive(:now).and_return(1002800)

      stats = {"exceptions" => @exceptions.stats,
               "empty_hash" => {},
               "float_value" => 3.15,
               "some % percent" => 3.54,
               "some time" => 0.675,
               "some rate" => 4.72,
               "some age" => 125,
               "activity1 %" => activity1.percentage,
               "activity1 last" => activity1.last,
               "activity2 %" => activity2.percentage,
               "activity2 last" => activity2.last,
               "activity3 last" => activity3.last,
               "some hash" => {"dogs" => 2, "cats" => 3, "hippopotami" => 99, "bears" => 1,
                               "ants" => 100000000, "dragons" => nil, "leopards" => 25}}

      result = sub_stats_str("my sub-stats", stats, 13)
      result.should == "my sub-stats  : activity1 %       : none\n" +
                       "                activity1 last    : none\n" +
                       "                activity2 %       : more testing: 75%, testing: 25%, total: 4\n" +
                       "                activity2 last    : more testing: 46 min, 40 sec ago\n" +
                       "                activity3 last    : testing forever: 46 min, 40 sec ago and still active\n" +
                       "                empty_hash        : none\n" +
                       "                exceptions        : testing total: 1, most recent:\n" +
                       "                                    (1) Mon Jan 12 05:46:40 -0800 1970 Exception: Test error\n" +
                       "                                        \n" +
                       "                float_value       : 3.2\n" +
                       "                some %            : 3.5%\n" +
                       "                some age          : 2 min, 5 sec\n" +
                       "                some hash         : ants: 100000000, bears: 1, cats: 3, dogs: 2, dragons: none, hippopotami: 99, \n" +
                       "                                    leopards: 25\n" +
                       "                some rate         : 4.7/sec\n" +
                       "                some time         : 0.68 sec\n"
    end

    it "should convert stats to a display string with special formatting for generic keys" do
      @exceptions.track("testing", Exception.new("Test error"))
      activity = RightScale::StatsHelper::ActivityStats.new
      activity.update("testing")
      flexmock(Time).should_receive(:now).and_return(1000010)
      sub_stats = {"exceptions" => @exceptions.stats,
                   "empty_hash" => {},
                   "float_value" => 3.15,
                   "activity %" => activity.percentage,
                   "activity last" => activity.last,
                   "some hash" => {"dogs" => 2, "cats" => 3, "hippopotami" => 99, "bears" => 1,
                                   "ants" => 100000000, "dragons" => nil, "leopards" => 25}}
      stats = {"stats time" => @now,
               "last reset time" => @now,
               "service uptime" => 3720,
               "machine uptime" => 183546,
               "version" => 10,
               "brokers" => @brokers,
               "hostname" => "localhost",
               "identity" => "unit tester",
               "stuff stats" => sub_stats}

      result = stats_str(stats)
      result.should == "identity    : unit tester\n" +
                       "hostname    : localhost\n" +
                       "stats time  : Mon Jan 12 05:46:40 -0800 1970\n" +
                       "last reset  : Mon Jan 12 05:46:40 -0800 1970\n" +
                       "service up  : 1 hr, 2 min\n" +
                       "machine up  : 2 days, 2 hr, 59 min\n" +
                       "version     : 10\n" +
                       "brokers     : b0: rs-broker-localhost-5672, status: connected, disconnects: 0, tries: 0\n" +
                       "              b1: rs-broker-localhost-5673, status: disconnected, disconnects: 1, tries: 0\n" +
                       "              exceptions        : none\n" +
                       "stuff       : activity %        : testing: 100%, total: 1\n" +
                       "              activity last     : testing: 10 sec ago\n" +
                       "              empty_hash        : none\n" +
                       "              exceptions        : testing total: 1, most recent:\n" +
                       "                                  (1) Mon Jan 12 05:46:40 -0800 1970 Exception: Test error\n" +
                       "                                      \n" +
                       "              float_value       : 3.2\n" +
                       "              some hash         : ants: 100000000, bears: 1, cats: 3, dogs: 2, dragons: none, hippopotami: 99, \n" +
                       "                                  leopards: 25\n"
    end

    it "should treat broker status, version, and machine uptime as optional" do
      sub_stats = {"exceptions" => @exceptions.stats,
                   "empty_hash" => {},
                   "float_value" => 3.15}

      stats = {"stats time" => @now,
               "last reset time" => @now,
               "service uptime" => 1000,
               "hostname" => "localhost",
               "identity" => "unit tester",
               "stuff stats" => sub_stats}

      result = stats_str(stats)
      result.should == "identity    : unit tester\n" +
                       "hostname    : localhost\n" +
                       "stats time  : Mon Jan 12 05:46:40 -0800 1970\n" +
                       "last reset  : Mon Jan 12 05:46:40 -0800 1970\n" +
                       "service up  : 16 min, 40 sec\n" +
                       "stuff       : empty_hash        : none\n" +
                       "              exceptions        : none\n" +
                       "              float_value       : 3.2\n"
    end

  end # Formatting

end # RightScale::StatsHelper
