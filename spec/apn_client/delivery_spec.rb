require 'spec_helper'

describe ApnClient::Delivery do
  before(:each) do
    token1 = "1b7b8de5888bb742ba744a2a5c8e52c6481d1deeecc283e830533b7c6bf1d099"
    payload1 = ApnClient::Payload.new(
      :alert => "New version of the app is out. Get it now in the app store!",
      :badge => 1
    )
    @message1 = ApnClient::Message.new(token1, payload1, :message_id => 1)

    token2 = "2a5g4de5888bb742ba744a2a5c8e52c6481d1deeecc283e830533b7c6bf1d044"
    payload2 = ApnClient::Payload.new(
      :alert => "New version of the app is out. Get it now in the app store!",
      :badge => 2
    )
    @message2 = ApnClient::Message.new(token2, payload2)

    token3 = "3a5g4de5888bb743ba744a2a5c8e52c6481d1deeecc283e830533b7c6bf1d044"
    payload3 = ApnClient::Payload.new(
      :alert => "New version of the app is out. Get it now in the app store!",
      :badge => 3
    )
    @message3 = ApnClient::Message.new(token3, payload3)

    @connection_config = {
      :host => 'gateway.push.apple.com',
      :cert => mock("certificate")
    }

    @messages = [@message1, @message2, @message3]
    @options  = {:connection_config => @connection_config}
  end

  describe '#initialize' do

    context "with valid options" do

      it "initializes attributes to default values" do
        delivery = ApnClient::Delivery.new(@messages, @options)
        delivery.messages.to_a.should == @messages

        delivery.connection_config.should == @connection_config
        delivery.connection_pool.should be_nil

        delivery.exception_limit.should == 20
        delivery.exception_limit_per_message.should == 3

        delivery.final_timeout.should == 2.0
        delivery.poll_timeout.should  == 0.1

        delivery.callbacks.should  == {}

        delivery.exceptions_per_message.should == {}
        delivery.exceptions.should == []
      end

      [
        :connection_pool,
        :exception_limit,
        :exception_limit_per_message,
        :poll_timeout,
        :final_timeout,
        :callbacks
      ].each do |option|
        context "given option #{option.inspect}" do
          before { @options.merge!(option => (@val = mock(option.to_s))) }

          it "should accept and store it" do
            ApnClient::Delivery.new(@messages, @options).send(option).should == @val
          end
        end
      end

    end

    context "with messages that doesn't respond to #to_enum" do
      before { @messages.expects(:to_enum).raises(RuntimeError) }
      it "should raise" do
        begin; ApnClient::Delivery.new(@messages, @options); rescue => e; end
        e.should be_an(RuntimeError)
      end
    end

    context "without option connection_config" do
      before { @options.delete(:connection_config) }
      it "should raise" do
        begin; ApnClient::Delivery.new(@messages, @options); rescue => e; end
        e.should be_an(ArgumentError)
      end
    end
  end

  describe "Connection Managment methods" do
    subject { ApnClient::Delivery.new(@messages, @options) }
    before(:each) do
      subject.stubs(:connection_config).returns(@connection_config = mock('connection_config'))
    end

    context 'with connection pool' do
      before(:each) do
        subject.stubs(:connection_pool).returns(@connection_pool = mock('connection_pool'))
      end

      describe '#connection' do
        it 'should #pop a connection from connection pool and cache it in @connection' do
          @connection_pool.expects(:pop).returns(connection = mock('connection'))
          subject.send(:connection).should == connection
          subject.instance_variable_get(:'@connection').should == connection

          # Test that we get same instance again
          subject.send(:connection).should be_equal(connection)
        end
      end

      describe '#reset_connection!' do
        it 'should call #close on @connection and reassign new ApnClient::Connection based on connection_config' do
          # We should not access through #connector
          subject.expects(:connection).never

          subject.instance_variable_set(:'@connection', old_connection = mock('old connection'))
          old_connection.expects(:close)
          ApnClient::Connection.expects(:new).with(@connection_config).\
            returns(new_connection = mock('new connection'))

          subject.send(:reset_connection!)

          subject.instance_variable_get(:'@connection').should == new_connection
        end
      end

      describe '#release_connection' do
        it 'should #push connection to connection pool and unset @connection' do
          # We should not access through #connector
          subject.expects(:connection).never

          subject.instance_variable_set(:'@connection', connection = mock('connection'))
          connection.expects(:close).never
          @connection_pool.expects(:push).with(connection)

          subject.send(:release_connection)

          subject.instance_variable_get(:'@connection').should be_nil
        end
      end
    end

    context 'without a connection pool' do
      before(:each) do
        subject.stubs(:connection_pool).returns(@connection_pool = nil)
      end

      describe '#connection' do
        it 'should create a connection using connection config and cache it in @connection' do
          ApnClient::Connection.expects(:new).with(@connection_config).\
            returns(connection = mock('connection'))
          subject.send(:connection).should == connection
          subject.instance_variable_get(:'@connection').should == connection

          # Test that we get same instance again
          subject.send(:connection).should be_equal(connection)
        end
      end

      describe '#reset_connection' do
        it 'should call #close on @connection and reassign new ApnClient::Connection based on connection_config' do
          # We should not access through #connector
          subject.expects(:connection).never

          subject.instance_variable_set(:'@connection', old_connection = mock('old connection'))
          old_connection.expects(:close)
          ApnClient::Connection.expects(:new).with(@connection_config).\
            returns(new_connection = mock('new connection'))

          subject.send(:reset_connection!)

          subject.instance_variable_get(:'@connection').should == new_connection
        end
      end

      describe '#release_connection' do
        it 'should call #close on connection and unset @connection' do
          # We should not access through #connector
          subject.expects(:connection).never

          subject.instance_variable_set(:'@connection', connection = mock('connection'))
          connection.expects(:close)

          subject.send(:release_connection)

          subject.instance_variable_get(:'@connection').should be_nil
        end
      end
    end

  end

  describe "#process!" do
    context 'given a valid delivery instance with 3 messages' do
      before(:each) do
        @writes, @apns_errors, @message_skips, @exceptions = [], [], [], []
        @options.merge!(
          :callbacks => {
            :on_write        => lambda { |*args| @writes << args },
            :on_apns_error   => lambda { |*args| @apns_errors << args },
            :on_message_skip => lambda { |*args| @message_skips << args },
            :on_exception    => lambda { |*args| @exceptions << args }
          }
        )
        @delivery = ApnClient::Delivery.new(@messages.first(3),@options)
        @delivery.expects(:connection).at_least_once.\
          returns(@connection = mock('connection'))
        @delivery.expects(:release_connection).once

        @delivery.stubs(:final_timeout).returns(@final_timeout = mock('final_timeout'))

        @delivery.expects(:poll_timeout).at_least_once.
          returns(@poll_timeout = mock('poll_timeout'))
      end

      context 'when no errors occur' do
        before(:each) do
          @connection.stubs(:readable?).with(@final_timeout).returns(false)

          @connection.expects(:availability).with(@poll_timeout).times(6).\
            returns([false, false]).then.\
            returns([false, false]).then.\
            returns([false, true]).then.\
            returns([false, false]).then.\
            returns([false, true]).then.\
            returns([false, true])
        end

        it "should write all messages to socket" do
          write_seq = sequence('writes')
          @connection.expects(:write).with(@messages[0].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[1].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[2].to_apns).\
            in_sequence(write_seq)

          @delivery.process!
        end

        it "should call on_write callbacks" do
          @connection.stubs(:write)

          @delivery.process!

          @writes.should == [@delivery,@delivery,@delivery].zip(@messages)
        end

      end

      context 'when socket indicates readability' do
        context "during run loop" do
          before(:each) do
            @connection.stubs(:readable?).with(@final_timeout).returns(false)
          end

          it "should not do anything fancy if #read_apns_error returns nil" do
            @connection.expects(:read_apns_error).twice.returns(nil)
            @connection.expects(:availability).with(@poll_timeout).times(6).\
              returns([false, false]).then.\
              returns([true, false]).then.\
              returns([false, true]).then.\
              returns([false, false]).then.\
              returns([false, true]).then.\
              returns([true, true])

            write_seq = sequence('writes')
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq)

            @delivery.process!

            @apns_errors.should be_empty
          end

          it "should reset_socket if #read_apns_error returns error code that's not in the messages array" do
            apns_error = [8,1,((1..1000).to_a - @messages.map(&:message_id)).sample]
            @connection.expects(:read_apns_error).times(3).\
              returns(nil).then.\
              returns(apns_error).then.\
              returns(nil)
            @connection.expects(:availability).with(@poll_timeout).times(7).\
              returns([false, false]).then.\
              returns([true, false]).then.\
              returns([false, true]).then.\
              returns([false, false]).then.\
              returns([false, true]).then.\
              returns([true, true]).then.\
              returns([true, true])

            write_seq = sequence('writes')
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq)
            @delivery.expects(:reset_connection!).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq)

            @delivery.process!

            @apns_errors.should == [[@delivery, apns_error[1], apns_error[2]]]
          end

          it "should resend messages sent after if #read_apns_error returns error code for message id in messages array" do
            @connection.expects(:read_apns_error).times(3).\
              returns(nil).then.\
              returns([8,7,@messages[0].message_id]).then.\
              returns(nil)
            @connection.expects(:availability).with(@poll_timeout).times(8).\
              returns([false, false]).then.\
              returns([true, false]).then.\
              returns([false, true]).then.\
              returns([false, false]).then.\
              returns([false, true]).then.\
              returns([true, true]).then.\
              returns([true, true]).then.\
              returns([nil, true])

            write_seq = sequence('writes')
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq)
            @delivery.expects(:reset_connection!).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq)

            @delivery.process!

            @apns_errors.should == [[@delivery,7,@messages[0].message_id]]
          end
        end
        context "durin final check" do
          before(:each) do
            @connection.stubs(:availability).with(@poll_timeout).returns([false, true])
          end

          it "should not do anything fancy if #read_apns_error returns nil" do
            @connection.expects(:readable?).with(@final_timeout).returns(true)
            @connection.expects(:read_apns_error).returns(nil)

            write_seq = sequence('writes')
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq)

            @delivery.process!

            @apns_errors.should be_empty
          end

          it "should not do anything fancy if #read_apns_error returns error code that's not in the messages array" do
            @connection.expects(:readable?).with(@final_timeout).returns(true)
            apns_error = [8,1,((1..1000).to_a - @messages.map(&:message_id)).sample]
            @connection.expects(:read_apns_error).returns(apns_error)

            write_seq = sequence('writes')
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq)

            @delivery.process!

            @apns_errors.should == [[@delivery, apns_error[1], apns_error[2]]]
          end

          it "should resend messages sent after if #read_apns_error returns error code for message id in messages array" do
            @connection.expects(:readable?).twice.with(@final_timeout).times(2).\
              returns(true).then.returns(false)
            @connection.expects(:read_apns_error).returns([8,4,@messages[1].message_id])

            write_seq = sequence('writes')
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq)

            @delivery.process!

            @apns_errors.should == [[@delivery, 4, @messages[1].message_id]]
          end
        end
      end

      context 'when errors occur' do
        it "should handle exception in connection#availability and still send message" do
          @connection.expects(:availability).with(@poll_timeout).at_least(2).\
            raises(RuntimeError).then.\
            returns([nil, true])

          write_seq = sequence('writes')
          @connection.expects(:write).with(@messages[0].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[1].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[2].to_apns).\
            in_sequence(write_seq)

          @delivery.expects(:reset_connection!)
          @delivery.expects(:read_final_error).times(2)

          @delivery.process!

          @exceptions.size.should == 1
          @exceptions.each { |e| e[0].should == @delivery; e[1].should be_an(RuntimeError) }
        end

        it "should handle exception in #read_error and still send message" do
          @connection.stubs(:availability).with(@poll_timeout).\
            returns([true, true])
          @delivery.expects(:read_error).times(4).\
            raises(IOError).then.\
            returns(nil)

          write_seq = sequence('writes')
          @connection.expects(:write).with(@messages[0].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[1].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[2].to_apns).\
            in_sequence(write_seq)

          @delivery.expects(:reset_connection!)
          @delivery.expects(:read_final_error).times(2)

          @delivery.process!

          @exceptions.size.should == 1
          @exceptions.each { |e| e[0].should == @delivery; e[1].should be_an(IOError) }
        end

        it "should handle exception in #write_message and still send message" do
          @connection.stubs(:availability).with(@poll_timeout).\
            returns([false, true])

          write_seq = sequence('writes')
          @connection.expects(:write).with(@messages[0].to_apns).\
            in_sequence(write_seq).raises(IOError)
          @connection.expects(:write).with(@messages[0].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[1].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[2].to_apns).\
            in_sequence(write_seq)

          @delivery.expects(:reset_connection!)
          @delivery.expects(:read_final_error).times(2)

          @delivery.process!

          @exceptions.size.should == 1
          @exceptions.each { |e| e[0].should == @delivery; e[1].should be_an(IOError) }
        end

        it "should handle exception in #read_final_error and still send message" do
          @connection.stubs(:availability).with(@poll_timeout).\
            returns([false, true])
          @delivery.expects(:read_final_error).times(2).\
            raises(IOError).then.\
            returns(nil)

          write_seq = sequence('writes')
          @connection.expects(:write).with(@messages[0].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[1].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[2].to_apns).\
            in_sequence(write_seq)

          @delivery.expects(:reset_connection!)

          @delivery.process!

          @exceptions.size.should == 1
          @exceptions.each { |e| e[0].should == @delivery; e[1].should be_an(IOError) }
        end

        it "should handle exception in #read_final_error in exception handling and still send message" do
          @connection.stubs(:availability).with(@poll_timeout).\
            returns([false, true])
          @delivery.expects(:read_final_error).times(2).\
            raises(IOError).then.\
            raises(IOError)

          write_seq = sequence('writes')
          @connection.expects(:write).with(@messages[0].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[1].to_apns).\
            in_sequence(write_seq)
          @connection.expects(:write).with(@messages[2].to_apns).\
            in_sequence(write_seq)

          @delivery.expects(:reset_connection!)

          @delivery.process!

          @exceptions.size.should == 1
          @exceptions.each { |e| e[0].should == @delivery; e[1].should be_an(IOError) }
        end

        it "should handle exceptions according to  exception_limit and exception_limit_per_message" do
          @connection.stubs(:availability).with(@poll_timeout).\
            returns([false, true])
          @connection.stubs(:readable?).with(@final_timeout).\
            returns(false)

          @delivery.stubs(:exception_limit).returns(8)
          @delivery.stubs(:exception_limit_per_message).returns(3)

          write_seq = sequence('writes')
          3.times do
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq).raises(IOError)
          end
          3.times do
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq).raises(IOError)
          end
          2.times do
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq).raises(IOError)
          end

          @delivery.expects(:reset_connection!).times(8)

          lambda { @delivery.process! }.should raise_error(ApnClient::ExceptionLimitReached)

          @exceptions.size.should == 8
          @exceptions.each { |e| e[0].should == @delivery; e[1].should be_an(IOError) }
        end

        context 'and socket returns readability' do
          it "should just reset connection and move on if #read_apns_error returns nil" do
            @connection.stubs(:availability).with(@poll_timeout).\
              returns([false, true])
            @connection.stubs(:readable?).with(@final_timeout).times(2).\
              returns(true).then.\
              returns(false)
            @connection.expects(:read_apns_error).returns(nil)

            @delivery.stubs(:exception_limit).returns(8)
            @delivery.stubs(:exception_limit_per_message).returns(3)

            write_seq = sequence('writes')
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq).raises(IOError)
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq)

            @delivery.expects(:reset_connection!).times(1)

            @delivery.process!

            @exceptions.size.should == 1
            @exceptions.each { |e| e[0].should == @delivery; e[1].should be_an(IOError) }

            @apns_errors.should be_empty
          end

          it "should just move on if #read_apns_error returns error code that's not in the messages array" do
            @connection.stubs(:availability).with(@poll_timeout).\
              returns([false, true])
            @connection.stubs(:readable?).with(@final_timeout).times(2).\
              returns(true).then.\
              returns(false)
            apns_error = [8,7,((1..1000).to_a-@messages.map(&:message_id)).sample]
            @connection.expects(:read_apns_error).\
              returns(apns_error)

            @delivery.stubs(:exception_limit).returns(8)
            @delivery.stubs(:exception_limit_per_message).returns(3)

            write_seq = sequence('writes')
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq).raises(IOError)
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq)

            @delivery.expects(:reset_connection!).times(1)

            @delivery.process!

            @exceptions.size.should == 1
            @exceptions.each { |e| e[0].should == @delivery; e[1].should be_an(IOError) }

            @apns_errors.should == [[@delivery, apns_error[1], apns_error[2]]]
          end

          it "should resend messages sent after if #read_apns_error returns error code for message id in messages array" do
            @connection.stubs(:availability).with(@poll_timeout).\
              returns([false, true])
            @connection.stubs(:readable?).with(@final_timeout).times(2).\
              returns(true).then.\
              returns(false)
            @connection.expects(:read_apns_error).\
              returns([8,7,@messages[0].message_id])

            @delivery.stubs(:exception_limit).returns(8)
            @delivery.stubs(:exception_limit_per_message).returns(3)

            write_seq = sequence('writes')
            @connection.expects(:write).with(@messages[0].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq).raises(IOError)
            @connection.expects(:write).with(@messages[1].to_apns).\
              in_sequence(write_seq)
            @connection.expects(:write).with(@messages[2].to_apns).\
              in_sequence(write_seq)

            @delivery.expects(:reset_connection!).times(1)

            @delivery.process!

            @exceptions.size.should == 1
            @exceptions.each { |e| e[0].should == @delivery; e[1].should be_an(IOError) }

            @apns_errors.should == [[@delivery, 7, @messages[0].message_id]]
          end
        end
      end

    end
  end

end
