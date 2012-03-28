require 'socket'
require 'openssl'

module ApnClient
  class Connection
    attr_reader :tcp_socket, :ssl_socket

    # Opens an SSL socket for talking to the Apple Push Notification service.
    #
    # @param [String] host the hostname to connect to
    # @param [String] cert the APN certificate to use
    # @param [String] cert_pass the passphrase of the certificate (default empty)
    def initialize(config = {})
      cert              = config[:cert]             || raise(ArgumentError, "Missing option 'cert'")
      host              = config[:host]             || raise(ArgumentError, "Missing option 'host'")
      pass              = config[:cert_pass]        || ''
      port              = 2195

      ssl_ctx = OpenSSL::SSL::SSLContext.new
      ssl_ctx.key = OpenSSL::PKey::RSA.new(cert, pass)
      ssl_ctx.cert = OpenSSL::X509::Certificate.new(cert)

      @tcp_socket = TCPSocket.new(host, port)
      @ssl_socket = OpenSSL::SSL::SSLSocket.new(@tcp_socket, ssl_ctx)
      @ssl_socket.sync = true
      @ssl_socket.connect
    end

    def close
      self.ssl_socket.close
      self.tcp_socket.close
    end

     def write(*args)
       self.ssl_socket.write(*args)
     end

     # Returns array [command, error_code, message_id]
     def read_apns_error
       @read_apns_buffer ||= ''

       response = self.ssl_socket.read_nonblock(6 - @read_apns_buffer.bytesize)
       @read_apns_buffer << response if response

       if @read_apns_buffer.bytesize == 6
         @read_apns_buffer.unpack('ccI').tap { @read_apns_buffer.clear }
       end
     rescue Errno::EAGAIN
       nil
     end

     def readable?(timeout)
       if res = IO.select([self.ssl_socket], nil, nil, timeout)
         res[0].size > 0
       else
         nil
       end
     end

     def availability(timeout)
       if res = IO.select([self.ssl_socket], [self.ssl_socket], nil, timeout)
         [res[0].size > 0, res[1].size > 0]
       else
         [nil, nil]
       end
     end

  end
end
