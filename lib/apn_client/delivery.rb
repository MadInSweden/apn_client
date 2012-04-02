module ApnClient
  class ExceptionLimitReached < Exception
    attr_reader :limit, :exceptions

    def initialize(delivery)
      @limit      = delivery.exception_limit
      @exceptions = delivery.exceptions
      super(self.message)
    end

    def message
      "Exception limit (#{self.limit}) reached, got these exceptions:\n\n".tap do |msg|
        self.exceptions.each { |e| msg << e.inspect << "\n\n" }
      end
    end
  end

  class Delivery
    # Required
    attr_reader :messages, :connection_config, :connection_pool,
                :exception_limit, :exception_limit_per_message,
                :poll_timeout, :final_timeout, :callbacks,
                :exceptions, :exceptions_per_message

    # Optional
    attr_reader :connection_pool

    # Public: Manages deliveries by looping over enumerable set of
    #         messages and sending them through ApnClient::Delivery
    #         instances.
    #
    # messages - A mutable array of ApnClient::Messages
    # options  - A hash of options
    #            :connection_config             - A connection config hash used to initialize ApnClient::Connection.
    #                                             (required)
    #            :connection_pool               - A connection pool responding to #pop and #push containing a set of ApnClient::Connection's.
    #                                             (optional, default: nil)
    #            :exception_limit               - An integer specifying maximum exceptions before raising ExceptionLimitReached.
    #                                             (optional, default: 20)
    #            :exception_limit_per_message   - An integer specifying maximum exceptions on sending
    #                                             specific message before moving on to the next message.
    #                                             (optional, default: 3)
    #            :poll_timeout                  - A Float timeout (seconds) used when doing IO.select on the socket.
    #                                             (optional, default 0.1)
    #            :final_timeout                 - A Float timeout (seconds) used when doing final IO.select on the socket.
    #                                             (optional, default 2.0)
    #            :callbacks                     - A hash with callbacks, available are:
    #                                             :on_write proc(ApnClient::Delivery, ApnClient::Message)
    #                                             :on_message_skip proc(ApnClient::Delivery, ApnClient::Message)
    #                                             :on_exception proc(ApnClient::Delivery, Exception, ApnClient::Message)
    #                                             :on_apns_error proc(ApnClient::Delivery, error_code, message_id)
    #                                             (optional, default: {})
    #
    def initialize(messages, options = {})
      @messages = messages.to_enum

      # Required
      @connection_config = options[:connection_config] || raise(ArgumentError, "Missing option 'connection_config'")

      # Optional
      @connection_pool               = options[:connection_pool]
      @exception_limit               = options[:exception_limit] || 20
      @exception_limit_per_message   = options[:exception_limit_per_message] || 3

      @final_timeout = options[:final_timeout] || 2.0
      @poll_timeout  = options[:poll_timeout]  || 0.1

      @callbacks = options[:callbacks] || {}

      @exceptions_per_message = Hash.new
      @exceptions             = []

      # Lazy loaded, will be a ApnClient::Connection during #process! call
      @connection = nil
    end

    # Public: Process (send) all messages in #messages to Apple.
    #
    # * If errors occur, the message is  retried a maximum of #exception_limit_per_message times.
    # * If apple writes error message, it will be read and message list will be rewinded to the
    #   apple specified message_id. If message with id is not in @messages, the message list
    #   pointer will not be changed.
    #
    # Raises ExceptionLimitReached if more then self.exception_limit exceptions occur.
    def process!
      loop do
        if has_next_message?
          readable, writable = connection.availability(self.poll_timeout)

          if readable and read_error
            reset_connection!
          elsif writable
            write_message
            next_message!
          end
        else
          reset_connection! if read_final_error
          return unless has_next_message?
        end
      end

    rescue Exception => e
      read_final_error rescue nil
      reset_connection!

      exception!(e)
      retry if has_next_message?
    ensure
      release_connection
    end

    private

      ### Main perform loop helpers

      def read_final_error
        read_error if connection.readable?(self.final_timeout)
      end

      def read_error
        command, error_code, message_id = connection.read_apns_error
        if message_id
          invoke_callback(:on_apns_error, error_code, message_id)
          rewind_messages!(message_id)
          return error_code
        end
      end

      def write_message
        connection.write(next_message.to_apns)
        invoke_callback(:on_write, next_message)
      end

      def exception!(e)
        invoke_callback(:on_exception, e)

        self.exceptions << e
        if self.exceptions.size >= self.exception_limit
          raise ExceptionLimitReached.new(self)
        end

        self.exceptions_per_message[next_message] ||= []
        self.exceptions_per_message[next_message] << e
        if self.exceptions_per_message[next_message].size >= self.exception_limit_per_message
          invoke_callback(:on_message_skip, next_message)
          next_message!
        end
      end

      ### Connection Managment

      def connection
        @connection ||= self.connection_pool ? self.connection_pool.pop : Connection.new(self.connection_config)
      end

      def reset_connection!
        @connection.close
        @connection = Connection.new(self.connection_config)
      end

      def release_connection
        self.connection_pool ? self.connection_pool.push(@connection) : @connection.close
        @connection = nil
      end

      ### Message managment

      # Internal: Returns the next message without incrementing pointer
      def next_message
        self.messages.peek
      rescue StopIteration
        nil
      end

      # Internal: Check if there is a next_message
      alias has_next_message? next_message

      # Internal: Returns the next message and increments pointer
      def next_message!
        self.messages.next
      rescue StopIteration
        nil
      end

      # Internal: Rewind to message _after_ message with message_id if it's
      #           available in #messages
      def rewind_messages!(message_id)

        if message = find_message(message_id)
          self.messages.rewind
          # We return after we move the pointer from message with message_id,
          # as we want to find the first non-failed message.
          while has_next_message?
            return if next_message! == message
          end
        end

      end

      # Internal: Find a message in messages by message_id
      def find_message(message_id)
        self.messages.find { |message| message.message_id == message_id }
      end

      ### Callbacks

      def invoke_callback(name, *args)
        self.callbacks[name].call(self, *args) if self.callbacks[name]
      end

  end
end
