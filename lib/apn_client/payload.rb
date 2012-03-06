require 'yajl'

module ApnClient
  PAYLOAD_MAX_SIZE = 256

  class PayloadToLarge < ArgumentError
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
    def initialize(rootless_payload)
      @json_str = Yajl.dump({'aps' => rootless_payload}).freeze
      @bytesize = @json_str.bytesize

      check_size!
    end

    def bytesize
      @bytesize
    end

    def to_json
      @json_str
    end

    private
      def check_size!
        raise(PayloadToLarge.new(self)) if self.bytesize > PAYLOAD_MAX_SIZE
      end
  end
end
