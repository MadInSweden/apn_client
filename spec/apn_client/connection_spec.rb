require 'spec_helper'

describe ApnClient::Connection do

  describe "#initialize" do

    for host in ['gateway.sandbox.push.apple.com', 'gateway.push.apple.com']
      for pass in ['test', '', nil]
        context "with valid config with host #{host.inspect} and cert_pass #{pass.inspect}" do
          before(:each) do
            @cert = mock("certificate")
            @host = host
            @pass = pass

            OpenSSL::SSL::SSLContext.expects(:new).returns(@ssl_ctx = mock("ssl_ctx"))
            OpenSSL::PKey::RSA.expects(:new).with(@cert, @pass || '').returns(@ssl_key = mock("ssl_key"))
            OpenSSL::X509::Certificate.expects(:new).with(@cert).returns(@ssl_cert = mock("ssl_cert"))

            @ssl_ctx.expects(:key=).with(@ssl_key)
            @ssl_ctx.expects(:cert=).with(@ssl_cert)

            TCPSocket.expects(:new).with(@host, 2195).returns(@tcp_socket = mock("tcp_socket"))

            OpenSSL::SSL::SSLSocket.expects(:new).with(@tcp_socket, @ssl_ctx).returns(@ssl_socket = mock("ssl_socket"))

            @ssl_socket.expects(:sync=).with(true)
            @ssl_socket.expects(:connect)

            @config = {:host => @host, :cert => @cert, :cert_pass => @pass}
          end

          it "opens a SSL connection and store the sockets" do
            connection = ApnClient::Connection.new(@config)

            connection.tcp_socket.should == @tcp_socket
            connection.ssl_socket.should == @ssl_socket
          end

        end
      end
    end

    for attr in [:host, :cert]
      context "with missing #{attr} in config" do
        before { @config = { :host => mock('host'), :cert => mock('cert'), :cert_pass => mock('cert_pass') } }
        before { @config.delete(attr) }

        it "should raise ArgumentError" do
          begin; ApnClient::Connection.new(@config); rescue => e; end
          e.should be_a(ArgumentError)
        end
      end
    end
  end

  describe "#close" do
    subject { ApnClient::Connection.allocate }

    it "closes ssl and tcp sockets" do
      subject.expects(:ssl_socket).returns(ssl_socket = mock('ssl_socket'))
      subject.expects(:tcp_socket).returns(tcp_socket = mock('tcp_socket'))

      ssl_socket.expects(:close)
      tcp_socket.expects(:close)

      subject.close
    end
  end

  describe "#write" do
    subject { ApnClient::Connection.allocate }

    it "invokes write on the ssl socket" do
      subject.expects(:ssl_socket).returns(ssl_socket = mock('ssl_socket'))
      ssl_socket.expects(:write).with(message = mock('message'))
      subject.write(message)
    end
  end

  describe "#read_apns_error" do
    subject { ApnClient::Connection.allocate }
    before(:each) do
      subject.expects(:ssl_socket).returns(@ssl_socket = mock('ssl_socket'))
    end

    context 'with no read buffer' do
      context 'on complete data' do
        before { @ssl_socket.expects(:read_nonblock).with(6).returns([8,7,(1<<(8*4) - 1)].pack('ccI')) }
        it "should unpack and return data" do
          subject.read_apns_error.should == [8,7,(1<<(8*4) - 1)]
          subject.instance_variable_get('@read_apns_buffer').should == ''
        end
      end

      context 'on too short data' do
        before { @ssl_socket.expects(:read_nonblock).with(6).returns([8,7,(1<<(8*4) - 1)].pack('cc')) }
        it "should buffer data and return nil" do
          subject.read_apns_error.should be_nil
          subject.instance_variable_get('@read_apns_buffer').should == [8,7].pack('cc')
        end
      end

      context 'on no nil' do
        before { @ssl_socket.expects(:read_nonblock).with(6).returns(nil) }
        it "should return nil" do
          subject.read_apns_error.should be_nil
          subject.instance_variable_get('@read_apns_buffer').should == ''
        end
      end

      context 'on no data' do
        before { @ssl_socket.expects(:read_nonblock).with(6).returns('') }
        it "should return nil" do
          subject.read_apns_error.should be_nil
          subject.instance_variable_get('@read_apns_buffer').should == ''
        end
      end

      context 'on Errno::EAGAIN' do
        before { @ssl_socket.expects(:read_nonblock).with(6).raises(Errno::EAGAIN) }
        it "should return nil" do
          subject.read_apns_error.should be_nil
          subject.instance_variable_get('@read_apns_buffer').should == ''
        end
      end

      context 'on IOError' do
        before { @ssl_socket.expects(:read_nonblock).with(6).raises(IOError) }
        it "should raise Errno::EINT" do
          begin; subject.read_apns_error; rescue => e; end
          e.should be_a(IOError)
          subject.instance_variable_get('@read_apns_buffer').should == ''
        end
      end
    end

    context 'with data in read buffer' do
      before(:each) { subject.instance_variable_set(:'@read_apns_buffer', [8,7].pack('cc')) }

      context 'on complete data' do
        before { @ssl_socket.expects(:read_nonblock).with(4).returns([(1<<(8*4) - 1)].pack('I')) }
        it "should unpack and return data" do
          subject.read_apns_error.should == [8,7,(1<<(8*4) - 1)]
          subject.instance_variable_get('@read_apns_buffer').should == ''
        end
      end

      context 'on too short data' do
        before { @ssl_socket.expects(:read_nonblock).with(4).returns([1].pack('c')) }
        it "should buffer data and return nil" do
          subject.read_apns_error.should be_nil
          subject.instance_variable_get('@read_apns_buffer').should == [8,7,1].pack('ccc')
        end
      end

      context 'on no nil' do
        before { @ssl_socket.expects(:read_nonblock).with(4).returns(nil) }
        it "should return nil" do
          subject.read_apns_error.should be_nil
          subject.instance_variable_get('@read_apns_buffer').should == [8,7].pack('cc')
        end
      end

      context 'on no data' do
        before { @ssl_socket.expects(:read_nonblock).with(4).returns('') }
        it "should return nil" do
          subject.read_apns_error.should be_nil
          subject.instance_variable_get('@read_apns_buffer').should == [8,7].pack('cc')
        end
      end

      context 'on Errno::EAGAIN' do
        before { @ssl_socket.expects(:read_nonblock).with(4).raises(Errno::EAGAIN) }
        it "should return nil" do
          subject.read_apns_error.should be_nil
          subject.instance_variable_get('@read_apns_buffer').should == [8,7].pack('cc')
        end
      end

      context 'on IOError' do
        before { @ssl_socket.expects(:read_nonblock).with(4).raises(IOError) }
        it "should raise Errno::EINT" do
          begin; subject.read_apns_error; rescue => e; end
          e.should be_a(IOError)
          subject.instance_variable_get('@read_apns_buffer').should == [8,7].pack('cc')
        end
      end
    end
  end

  describe "#readable?" do
    subject { ApnClient::Connection.allocate }
    before(:each) do
      @timeout = mock('timeout')
      subject.expects(:ssl_socket).returns(@ssl_socket = mock('ssl_socket'))
    end

    context "when select indicate readability" do
      before { IO.expects(:select).with([@ssl_socket], nil, nil, @timeout).returns([[@ssl_socket], [], []]) }
      it { should be_readable(@timeout) }
    end

    context "when select indicate none-readability" do
      before { IO.expects(:select).with([@ssl_socket], nil, nil, @timeout).returns([[], [], []]) }
      it { should_not be_readable(@timeout) }
    end

    context "when select returns nil" do
      before { IO.expects(:select).with([@ssl_socket], nil, nil, @timeout).returns(nil) }
      it { should_not be_readable(@timeout) }
    end

    context "when select raises IOError" do
      before { IO.expects(:select).with([@ssl_socket], nil, nil, @timeout).raises(IOError) }
      it "should raise IOError" do
        begin; subject.readable?(@timeout); rescue => e; end
        e.should be_an(IOError)
      end
    end
  end

  describe "#availability" do
    subject { ApnClient::Connection.allocate }
    before(:each) do
      @timeout = mock('timeout')
      subject.expects(:ssl_socket).times(2).returns(@ssl_socket = mock('ssl_socket'))
    end

    [[true, true], [false, false], [true, false], [false, true]].each do |readable,writeable|
      context "when select indicate #{'none-' unless readable}readable and #{'none-' unless writeable}writeable" do
        before { IO.expects(:select).with([@ssl_socket], [@ssl_socket], nil, @timeout).returns([readable ? [@ssl_socket] : [], writeable ? [@ssl_socket] : [], []]) }
        it { subject.availability(@timeout).should == [readable, writeable] }
      end
    end

    context "when select returns nil" do
      before { IO.expects(:select).with([@ssl_socket], [@ssl_socket], nil, @timeout).returns(nil) }
      it { subject.availability(@timeout).should == [nil,nil] }
    end

    context "when select raises IOError" do
      before { IO.expects(:select).with([@ssl_socket], [@ssl_socket], nil, @timeout).raises(IOError) }
      it "should raise IOError" do
        begin; subject.availability(@timeout); rescue => e; end
        e.should be_an(IOError)
      end
    end
  end


end
