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
      @stats.finish(1000010)
      @stats.instance_variable_get(:@interval).should == 0.0
      @stats.instance_variable_get(:@last_start_time).should == @now
      @stats.instance_variable_get(:@avg_duration).should == 2.0
      @stats.instance_variable_get(:@total).should == 0
      @stats.instance_variable_get(:@count_per_type).should == {}
    end

    it "should convert interval to rate" do
      flexmock(Time).should_receive(:now).and_return(1000020)
      @stats.update
      @stats.instance_variable_get(:@interval).should == 2.0
      @stats.avg_rate.should == 0.5
    end

    it "should report number of seconds since last update or nil if no updates" do
      flexmock(Time).should_receive(:now).and_return(1000010)
      @stats.last.should be_nil
      @stats.update
      @stats.last.should == 0
    end

    it "should convert count per type to percentages" do
      flexmock(Time).should_receive(:now).and_return(1000010)
      @stats.update("foo")
      @stats.instance_variable_get(:@total).should == 1
      @stats.instance_variable_get(:@count_per_type).should == {"foo" => 1}
      @stats.percent.should == {"total" => 1, "percent" => {"foo" => 100.0}}
      @stats.update("bar")
      @stats.instance_variable_get(:@total).should == 2
      @stats.instance_variable_get(:@count_per_type).should == {"foo" => 1, "bar" => 1}
      @stats.percent.should == {"total" => 2, "percent" => {"foo" => 50.0, "bar" => 50.0}}
      @stats.update("foo")
      @stats.update("foo")
      @stats.instance_variable_get(:@total).should == 4
      @stats.instance_variable_get(:@count_per_type).should == {"foo" => 3, "bar" => 1}
      @stats.percent.should == {"total" => 4, "percent" => {"foo" => 75.0, "bar" => 25.0}}
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
      @brokers = [{"identity"=>"rs-broker-localhost-5672", "tries"=>0, "alias"=>"b0", "status"=>"connected"},
                  {"identity"=>"rs-broker-localhost-5673", "tries"=>0, "alias"=>"b1", "status"=>"disconnected"}]
    end

    it "should convert count per type to percentages" do
      stats = {"first" => 1, "second" => 4, "third" => 3}
      result = percent(stats)
      result.should == {"total" => 8, "percent" => {"first" => 12.5, "second" => 50.0, "third" => 37.5}}
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

    it "should convert broker status to multi-line display string" do
      result = brokers_str(@brokers, 10)
      result.should == "brokers    : alias: b0, identity: rs-broker-localhost-5672, status: connected, tries: 0\n" +
                       "             alias: b1, identity: rs-broker-localhost-5673, status: disconnected, tries: 0\n"
    end

    it "should convert exception stats to multi-line string" do
      @exceptions.track("testing", Exception.new("Test error"))
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
                   "----(1) Mon Jan 12 05:46:40 -0800 1970 Exception: Test error\n" +
                   "----    "
    end

    it "should convert nested hash into string with keys sorted numerically if possible, else alphabetically" do
      hash = {"dogs" => 2, "cats" => 3, "hippopotami" => 99, "bears" => 1, "ants" => 100000000, "dragons" => nil,
              "food" => {"apples" => "bushels", "berries" => "lots", "meat" => {"fish" => 10.45, "beef" => nil}},
              "versions" => { "1" => 10, "5" => 50, "10" => 100} }
      result = hash_str(hash)
      result.should == "ants: 100000000, bears: 1, cats: 3, dogs: 2, dragons: none, " +
                       "food: [ apples: bushels, berries: lots, meat: [ beef: none, fish: 10.4 ] ], " +
                       "hippopotami: 99, versions: [ 1: 10, 5: 50, 10: 100 ]"
      result = wrap(result, 20, "----", ", ")
      result.should == "ants: 100000000, \n" +
                   "----bears: 1, cats: 3, \n" +
                   "----dogs: 2, \n" +
                   "----dragons: none, \n" +
                   "----food: [ apples: bushels, \n" +
                   "----berries: lots, \n" +
                   "----meat: [ beef: none, \n" +
                   "----fish: 10.4 ] ], \n" +
                   "----hippopotami: 99, \n" +
                   "----versions: [ 1: 10, \n" +
                   "----5: 50, 10: 100 ]"
    end

    it "should convert sub-stats to a display string" do
      @exceptions.track("testing", Exception.new("Test error"))
      activity = RightScale::StatsHelper::ActivityStats.new

      stats = {"exceptions" => @exceptions.stats,
               "empty_hash" => {},
               "float_value" => 3.1415,
               "activity percent" => activity.percent,
               "activity last" => activity.last,
               "some hash" => {"dogs" => 2, "cats" => 3, "hippopotami" => 99, "bears" => 1,
                               "ants" => 100000000, "dragons" => nil, "leopards" => 25}}

      result = sub_stats_str("my sub-stats", stats, 13)
      result.should == "my sub-stats  : activity last     : none\n" +
                       "                activity percent  : none\n" +
                       "                empty_hash        : none\n" +
                       "                exceptions        : testing total: 1, most recent:\n" +
                       "                                    (1) Mon Jan 12 05:46:40 -0800 1970 Exception: Test error\n" +
                       "                                        \n" +
                       "                float_value       : 3.142\n" +
                       "                some hash         : ants: 100000000, bears: 1, cats: 3, dogs: 2, dragons: none, hippopotami: 99, \n" +
                       "                                    leopards: 25\n"
    end

    it "should convert stats to a display string with special formatting for generic keys" do
      @exceptions.track("testing", Exception.new("Test error"))
      activity = RightScale::StatsHelper::ActivityStats.new
      activity.update("testing")
      flexmock(Time).should_receive(:now).and_return(1000010)
      sub_stats = {"exceptions" => @exceptions.stats,
                   "empty_hash" => {},
                   "float_value" => 3.1415,
                   "activity percent" => activity.percent,
                   "activity last" => activity.last,
                   "some hash" => {"dogs" => 2, "cats" => 3, "hippopotami" => 99, "bears" => 1,
                                   "ants" => 100000000, "dragons" => nil, "leopards" => 25}}
      stats = {"stats time" => @now,
               "last reset time" => @now,
               "version" => 10,
               "brokers" => @brokers,
               "hostname" => "localhost",
               "identity" => "unit tester",
               "stuff stats" => sub_stats}

      result = stats_str(stats)
      result.should == "stats time  : Mon Jan 12 05:46:40 -0800 1970\n" +
                       "last reset  : Mon Jan 12 05:46:40 -0800 1970\n" +
                       "hostname    : localhost\n" +
                       "identity    : unit tester\n" +
                       "brokers     : alias: b0, identity: rs-broker-localhost-5672, status: connected, tries: 0\n" +
                       "              alias: b1, identity: rs-broker-localhost-5673, status: disconnected, tries: 0\n" +
                       "version     : 10\n" +
                       "stuff       : activity last     : 10\n" +
                       "              activity percent  : percent: [ testing: 100.0 ], total: 1\n" +
                       "              empty_hash        : none\n" +
                       "              exceptions        : testing total: 1, most recent:\n" +
                       "                                  (1) Mon Jan 12 05:46:40 -0800 1970 Exception: Test error\n" +
                       "                                      \n" +
                       "              float_value       : 3.142\n" +
                       "              some hash         : ants: 100000000, bears: 1, cats: 3, dogs: 2, dragons: none, hippopotami: 99, \n" +
                       "                                  leopards: 25\n"
    end

    it "should treat broker status and version as optional" do
      sub_stats = {"exceptions" => @exceptions.stats,
                   "empty_hash" => {},
                   "float_value" => 3.1415}

      stats = {"stats time" => @now,
               "last reset time" => @now,
               "hostname" => "localhost",
               "identity" => "unit tester",
               "stuff stats" => sub_stats}

      result = stats_str(stats)
      result.should == "stats time  : Mon Jan 12 05:46:40 -0800 1970\n" +
                       "last reset  : Mon Jan 12 05:46:40 -0800 1970\n" +
                       "hostname    : localhost\n" +
                       "identity    : unit tester\n" +
                       "stuff       : empty_hash        : none\n" +
                       "              exceptions        : none\n" +
                       "              float_value       : 3.142\n"
    end

  end # Formatting

end # RightScale::StatsHelper
