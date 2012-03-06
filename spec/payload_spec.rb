require 'spec_helper'

describe ApnClient::Payload do
  describe "#initialize" do
    it "should raise if hash generates to large json" do
      lambda { ApnClient::Payload.new('a'*246) }.should_not raise_error(ApnClient::PayloadToLarge)
      lambda { ApnClient::Payload.new('a'*247) }.should     raise_error(ApnClient::PayloadToLarge)
      begin
        ApnClient::Payload.new('a'*247)
      rescue => e
        e.should be_a(ApnClient::PayloadToLarge)
        e.object.should be_a(ApnClient::Payload)
        e.message.should include('257 bytes')
      end
    end
  end

  describe "#bytesize" do

    it "should return correct bytesize of json" do
      payload = ApnClient::Payload.new({:alert => true})
      payload.bytesize.should == payload.to_json.bytesize
    end

  end

  describe "#to_json" do

    it "should return memoized, frozen json string with 'aps' root hash" do
      payload = ApnClient::Payload.new({:sound => 'l.aif'})

      # correct
      JSON.parse(payload.to_json).should == {'aps' => {'sound' => 'l.aif'}}

      # memoized
      payload.to_json.object_id == payload.to_json.object_id

      # frozen
      payload.to_json.should be_frozen
    end

  end

end
