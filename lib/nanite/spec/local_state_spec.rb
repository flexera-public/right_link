require File.join(File.dirname(__FILE__), 'spec_helper')
require 'nanite/local_state'

describe "Nanite::LocalState: " do

  describe "Class" do

    it "should a Hash" do
      Nanite::LocalState.new({}).should be_kind_of(Hash)
    end

    it "should create empty hash if no hash passed in" do
      Nanite::LocalState.new.should == {}
    end

    it "should initialize hash with value passed in" do
      state = Nanite::LocalState.new({:a => 1, :b => 2, :c => 3})
      state.should == {:a => 1, :b => 2, :c => 3}
    end

  end # Class

  describe "Nanites lookup" do

    before(:each) do
      @request = mock('Request', :type => "services", :tags => [])
      @request_for_b = mock('Request', :type => "b's services", :tags => [])
    end

    it "should find services matching the service criteria if no tags criteria is specified" do
      state = Nanite::LocalState.new({:a => { :services => "a's services" }, :b => { :services => "b's services" }})
      state.nanites_for(@request_for_b).should == {:b => {:services => "b's services"} }
    end

    it "should find all services matching the service criteria if no tags criteria is specified" do
      state = Nanite::LocalState.new({:a => { :services => "services" }, :b => { :services => "services" }, :c => { :services => "other services" }})
      state.nanites_for(@request).should include(:a)
      state.nanites_for(@request).should include(:b)
    end

    it "should only services matching the service criteria that also match the tags criteria" do
      state = Nanite::LocalState.new({:a => { :services => "a's services", :tags => ["a_1", "a_2"] }, :b => { :services => "b's services", :tags => ["b_1", "b_2"] }})
      state.nanites_for(@request_for_b).should == {:b => {:tags=>["b_1", "b_2"], :services=>"b's services"} }
    end
    
    it "should find all services with matching tags even if the tag order is different" do
      state = Nanite::LocalState.new({'a' => { :services => "services", :tags => ["a_1", "a_2"] }, 'b' => { :services => "services", :tags => ["a_2", "a_1"] }})
      @request.should_receive(:tags).and_return(['a_1', 'a_2'])
      state.nanites_for(@request).sort.should == [['a', {:tags=>["a_1", "a_2"], :services=>"services"}], ['b', {:tags=>["a_2", "a_1"], :services=>"services"}]]
    end

    it "should also return all tags for services matching the service criteria that also match a single tags criterium" do
      state = Nanite::LocalState.new({:a => { :services => "services", :tags => ["t_1", "t_2"] }})
      @request.should_receive(:tags).and_return(['t_1'])
      state.nanites_for(@request).should == {:a => {:tags=>["t_1", "t_2"], :services=>"services"} }
    end

    it "should return services matching the service criteria and also match the tags criterium" do
      state = Nanite::LocalState.new({:a => { :services => "a's services", :tags => ["a_1", "a_2"] }, :b => { :services => "b's services", :tags => ["b_1", "b_2"] }})
      @request.should_receive(:tags).and_return(['b_1'])
      state.nanites_for(@request).should == {:b => {:tags=>["b_1", "b_2"], :services=>"b's services"} }
    end

    it "should ignore services matching the service criteria and but not the tags criteria" do
      state = Nanite::LocalState.new({:a => { :services => "services", :tags => ["t_1", "t_2"] }, :b => { :services => "services", :tags => ["t_3", "t_4"] }})
      @request.should_receive(:tags).and_return(['t_1'])
      state.nanites_for(@request).should == {:a => {:services => "services", :tags => ["t_1", "t_2"]}}
    end

    it "should lookup services matching the service criteria and and any of the tags criteria" do
      state = Nanite::LocalState.new({'a' => { :services => "services", :tags => ["t_1", "t_2"] }, 'b' => { :services => "services", :tags => ["t_2", "t_3"] }})
      @request.should_receive(:tags).and_return(['t_1', 't_3'])
      state.nanites_for(@request).sort.should == [['a', {:services => "services", :tags => ["t_1", "t_2"]}], ['b', {:services => "services", :tags => ["t_2", "t_3"]}]]
    end

  end # Nanites lookup

  describe "Updating a Nanite's status" do
    it "should set the status for the nanite" do
      state = Nanite::LocalState.new('a' => { :services => "service" })
      state.update_status('a', 0.1)
      state['a'][:status].should == 0.1
    end
    
    it "should store the timestamp for the nanite" do
      state = Nanite::LocalState.new('a' => { :services => "service" })
      state.update_status('a', 0.1)
      state['a'][:timestamp].should be_close(Time.now.utc.to_i, 1)
    end
  end
end # Nanite::LocalState
