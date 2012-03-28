require 'spec_helper'

describe ApnClient::Message do
  before(:each) do
    @device_token = "7b7b8de5888bb742ba744a2a5c8e52c6481d1deeecc283e830533b7c6bf1d099"
    @other_device_token = "8c7b8de5888bb742ba744a2a5c8e52c6481d1deeecc283e830533b7c6bf5e699"

    alert = "Hello, check out version 9.5 of our awesome app in the app store"
    badge = 3

    @alert_payload = ApnClient::Payload.new(:alert => alert)
    @alertbadge_payload = ApnClient::Payload.new(:alert => alert, :badge => badge)
  end

  describe "#initialize" do
    it "can be created with device_token and payload" do
      t = Time.now
      Time.stubs(:now).returns(t)

      ApnClient::MessageId.expects(:next).returns(1 << (4*7))

      m = ApnClient::Message.new(@device_token, @alert_payload)
      m.device_token.should == @device_token
      m.payload.should      == @alert_payload
      m.message_id.should   == (1 << (4*7))
      m.expires_at.should   == (t + 30*60*60*24).to_i
    end

    it "can be created with device_token, payload and message_id" do
      t = Time.now
      Time.stubs(:now).returns(t)

      ApnClient::MessageId.expects(:next).never

      m = ApnClient::Message.new(@device_token, @alert_payload, :message_id => 1)
      m.device_token.should == @device_token
      m.payload.should      == @alert_payload
      m.message_id.should   == 1
      m.expires_at.should   == (t + 30*60*60*24).to_i
    end

    it "can be created with device_token, payload, message_id and expires_at" do
      t = Time.now + 30*60

      ApnClient::MessageId.expects(:next).never

      m = ApnClient::Message.new(@other_device_token, @alertbadge_payload, :message_id => 2, :expires_at => t)
      m.device_token.should == @other_device_token
      m.payload.should      == @alertbadge_payload
      m.message_id.should   == 2
      m.expires_at.should   == t.to_i
    end
  end

  describe "#to_apns" do

    context 'with low message_id' do
      it "should pack message as apns binary package" do
        # This was previously generated using previous gen of ApnClient::Message
        expected_sha1_hexdigest = "ebf4f6ad18feb35dd1d77a2289e2424bc89e8444"

        token   = "7b7b8de5888bb742ba744a2a5c8e52c6481d1deeecc283e830533b7c6bf1d099"
        payload = ApnClient::Payload.new(:alert => "asd", :badge => 3, :sound => "asd.aif")
        msg     = ApnClient::Message.new(token, payload, :message_id => 4096, :expires_at => Time.at(10920392).to_i)

        Digest::SHA1.hexdigest(msg.to_apns).should == expected_sha1_hexdigest
      end
    end

    context 'with high message_id' do
      it "should pack message as apns binary package" do
        expected_sha1_hexdigest = "dab1d431edbb3935f4868710c4c9f86476b369e4"

        token   = "7b7b8de5888bb742ba744a2a5c8e52c6481d1deeecc283e830533b7c6bf1d099"
        payload = ApnClient::Payload.new(:alert => "asd", :badge => 3, :sound => "asd.aif")
        msg     = ApnClient::Message.new(token, payload, :message_id => ((1 << (8*4)) - 1), :expires_at => Time.at(10920392).to_i)

        Digest::SHA1.hexdigest(msg.to_apns).should == expected_sha1_hexdigest
      end
    end

  end


end
