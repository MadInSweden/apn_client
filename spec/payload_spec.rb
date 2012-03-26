require 'spec_helper'

describe ApnClient::Payload do
  describe "#initialize" do
    it "should raise if hash generates to large json" do
      lambda { ApnClient::Payload.new('a'*246) }.should_not raise_error(ApnClient::PayloadTooLarge)
      lambda { ApnClient::Payload.new('a'*247) }.should     raise_error(ApnClient::PayloadTooLarge)
      begin
        ApnClient::Payload.new('a'*247)
      rescue => e
        e.should be_a(ApnClient::PayloadTooLarge)
        e.object.should be_a(ApnClient::Payload)
        e.message.should include('257 bytes')
      end
    end
  end

  describe "#bytesize" do

    it "should return correct bytesize of json" do
      payload = ApnClient::Payload.new(:alert => true)
      payload.bytesize.should == payload.to_json.bytesize
    end

  end

  describe "#to_json" do

    it "should return memoized, frozen string" do
      payload = ApnClient::Payload.new(:sound => 'l.aif')

      # memoized
      payload.to_json.object_id == payload.to_json.object_id

      # frozen
      payload.to_json.should be_frozen
    end

    it "should be a json string of aps hash if only inited with aps hash" do
      payload = ApnClient::Payload.new(:sound => 'l.aif')
      Yajl.load(payload.to_json).should == {'aps' => {'sound' => 'l.aif'}}
    end

    it "should be a json string of aps hash and custom hash if both are given" do
      payload = ApnClient::Payload.new({:sound => 'l.aif'}, {:id => 103})
      Yajl.load(payload.to_json).should == {'aps' => {'sound' => 'l.aif'}, 'custom' => {'id' => 103}}
    end

    it "should innclude memoized, frozen json string with 'aps' root hash" do
      payload = ApnClient::Payload.new(:sound => 'l.aif')

      # correct
      Yajl.load(payload.to_json).should == {'aps' => {'sound' => 'l.aif'}}

      # memoized
      payload.to_json.object_id == payload.to_json.object_id

      # frozen
      payload.to_json.should be_frozen
    end

  end

end
