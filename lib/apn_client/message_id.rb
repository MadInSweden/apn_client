require 'thread'

module ApnClient
  # Thread-safe message_id generator
  module MessageId extend self
    MUTEX = Mutex.new

    def next
      synchronize { return next_message_id }
    end

    private
      def synchronize
        MUTEX.synchronize { yield }
      end

      # We limit this to be less than 4 bytes since that's the maximum that fits in the
      # field we'll put it in.
      def next_message_id
        if not @message_id
          @message_id  = 1
        else
          @message_id += 1
        end

        @message_id < (1 << (4*8)) ?  @message_id : (@message_id = 1)
      end
  end
end
