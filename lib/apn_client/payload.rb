require 'yajl'

module ApnClient
  PAYLOAD_MAX_SIZE = 256

  class PayloadTooLarge < ArgumentError
    attr_reader :object

    def initialize(object)
      @object = object
      super(self.message)
    end

    def message
      "Payload generates a JSON string of #{self.object.bytesize} bytes, max is #{PAYLOAD_MAX_SIZE} bytes."
    end

  end

  class Payload

    # Creates a payload that's used by ApnClient::Message to build
    # message to send to APN.
    #
    # @param [Hash] rootless_aps The aps data to send to apple, without the 'aps' root node.
    # @param [Hash] rootless_customs The custom data to send to apple, without the 'custom' root node.
    #
    class << self
      def logger
        @logger ||= Logger.new(Rails.root.join('log').join('apn_client.log'))
      end

      def logger=(logger)
        @logger = logger
      end
    end

    def initialize(rootless_aps, rootless_custom = nil)
      payload = {}
      payload['aps'] = rootless_aps
      payload['custom'] = rootless_custom if rootless_custom

      @json_str = Yajl.dump(payload).freeze
      @bytesize = @json_str.bytesize

      check_size!
    end

    # Returns bytesize of JSON payload
    def bytesize
      @bytesize
    end

    # Returns JSON payload
    def to_json
      @json_str
    end

    private
      def check_size!
        if self.bytesize > PAYLOAD_MAX_SIZE
          Payload.logger.error("Payload too big: '#{self.to_json}'")
          raise(PayloadTooLarge.new(self))
        end
      end
  end
end
