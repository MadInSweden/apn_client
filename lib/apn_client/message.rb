module ApnClient

  class Message

    # Attributes
    attr_reader :message_id, :device_token, :expires_at, :payload

    # Creates an APN message to to be sent over SSL to the APN service.
    #
    # @param [String] device_token The device token as hex string (without spaces etc)
    # @param [ApnClient::Payload] payload The message payload
    # @param [Time] expires_at Expire time, will be set as integer (default now + 30 days)
    # @param [Fixnum] message_id Message id as integer (default nil, nil will get overriden by ApnClient::Delivery)
    #
    def initialize(device_token, payload, options = {})
      @device_token = device_token
      @payload      = payload

      @expires_at = (options[:expires_at] ? options[:expires_at] : (Time.now + 30*60*60*24)).to_i
      @message_id =  options[:message_id] || MessageId.next
    end

    # Pack APNS message in enhanced binary format
    def to_apns
      [
        1,
        self.message_id,
        self.expires_at,
        0,
        32,
        self.device_token,
        0,
        self.payload.bytesize,
        self.payload.to_json
      ].pack('cIiccH*cca*')
    end
  end
end
