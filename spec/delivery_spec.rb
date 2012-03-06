require 'spec_helper'

describe ApnClient::Delivery do
  before(:each) do
    token1 = "7b7b8de5888bb742ba744a2a5c8e52c6481d1deeecc283e830533b7c6bf1d099"
    payload1 = ApnClient::Payload.new(
      :alert => "New version of the app is out. Get it now in the app store!",
      :badge => 2
    )
    @message1 = ApnClient::Message.new(token1, payload1, :message_id => 1)

    token2 = "6a5g4de5888bb742ba744a2a5c8e52c6481d1deeecc283e830533b7c6bf1d044"
    payload2 = ApnClient::Payload.new(
      :alert => "New version of the app is out. Get it now in the app store!",
      :badge => 1
    )
    @message2 = ApnClient::Message.new(token2, payload2)

    @connection_config = {
        :host => 'gateway.push.apple.com',
        :port => 2195,
        :certificate => "certificate",
        :certificate_passphrase => ''
    }
  end

  describe "#initialize" do
    it "initializes counts and other attributes" do
      delivery = create_delivery([@message1, @message2], :connection_config => @connection_config)
      delivery.connection_config.should == @connection_config
    end

    it "should accept provided connection_pool" do
      pool = mock("pool")
      delivery = create_delivery([@message1, @message2], :connection_config => @connection_config,
                                                         :connection_pool => pool)
      delivery.connection_pool.should == pool
    end
  end

  describe "connection managment" do
    before(:each) do
      @delivery = create_delivery([@message1, @message2], :connection_config => @connection_config)
    end

    describe "with connection pool" do
      before(:each) do
        @pool = mock("pool")
        @delivery.connection_pool = @pool
      end

      it "#connection should #pop connection from connection pool and memoize it" do
        connection = mock('connection')
        @pool.expects(:pop).once.returns(connection)

        @delivery.instance_variable_set(:'@connection', nil)

        @delivery.send(:connection).should == connection
        @delivery.send(:connection).should == connection
        @delivery.instance_variable_get(:'@connection').should == connection
      end

      it "#release_connection should #push connection to connection pool and nil it out" do
        connection = mock('connection')
        @delivery.instance_variable_set(:'@connection', connection)
        @pool.expects(:push).with(connection).once

        @delivery.send(:release_connection)

        @delivery.instance_variable_get(:'@connection').should == nil
      end

    end

    describe "without connection pool" do
      before(:each) do
        @delivery.connection_pool = nil
      end

      it "#connection should create new ApnClient::Connection and memoize it" do
        connection = mock('connection')
        ApnClient::Connection.expects(:new).once.returns(connection)

        @delivery.instance_variable_set(:'@connection', nil)

        @delivery.send(:connection).should == connection
        @delivery.send(:connection).should == connection
        @delivery.instance_variable_get(:'@connection').should == connection
      end

      it "#release_connection should send close to @connection and nil it out" do
        connection = mock('connection')
        connection.expects(:close).once
        @delivery.instance_variable_set(:'@connection', connection)

        @delivery.send(:release_connection)

        @delivery.instance_variable_get(:'@connection').should == nil
      end

    end

    describe "#reset_connection!" do
      it "should close old connection and assign a new one to @connection" do
        connection = mock('connection')
        connection.expects(:close).once
        @delivery.instance_variable_set(:'@connection', connection)

        new_connection = mock('connection')
        ApnClient::Connection.stubs(:new).returns(new_connection)

        @delivery.send(:reset_connection!)

        @delivery.instance_variable_get(:'@connection').should == new_connection
      end
    end

  end



  describe "#process!" do
    it "can deliver to all messages successfully and invoke on_write callback" do
      messages = [@message1, @message2]
      written_messages = []
      nil_selects = 0
      callbacks = {
          :on_write => lambda { |d, m| written_messages << m },
          :on_nil_select => lambda { |d| nil_selects += 1 }
        }
      delivery = create_delivery(messages.dup, :callbacks => callbacks, :connection_config => @connection_config)


      connection = mock('connection')

      connection.expects(:next_message_id).returns(5)
      @message2.expects(:message_id=).with(5)
      @message1.expects(:message_id=).never

      apns = mock('apnsstr')
      @message2.stubs(:to_apns).returns(apns)

      connection.expects(:write).with(@message1.to_apns)
      connection.expects(:write).with(@message2.to_apns)
      connection.expects(:select).times(2).returns(nil)
      delivery.stubs(:connection).returns(connection)
      delivery.expects(:release_connection).once

      delivery.process!

      delivery.failure_count.should == 0
      delivery.success_count.should == 2
      delivery.total_count.should == 2
      written_messages.should == messages
      nil_selects.should == 2
    end

    it "fails a message if it fails more than 3 times" do
      messages = [@message1, @message2]
      written_messages = []
      exceptions = []
      failures = []
      read_exceptions = []
      callbacks = {
          :on_write => lambda { |d, m| written_messages << m },
          :on_exception => lambda { |d, e| exceptions << e },
          :on_failure => lambda { |d, m| failures << m },
          :on_read_exception => lambda { |d, e| read_exceptions << e }
        }
      delivery = create_delivery(messages.dup, :callbacks => callbacks, :connection_config => @connection_config)

      connection = mock('connection')

      connection.expects(:next_message_id).returns(4)
      @message2.expects(:message_id=).with(4)
      @message1.expects(:message_id=).never

      apns = mock('apnsstr')
      @message2.stubs(:to_apns).returns(apns)

      connection.expects(:write).with(@message1.to_apns).times(3).raises(RuntimeError)
      connection.expects(:write).with(@message2.to_apns)
      connection.expects(:select).times(4).raises(RuntimeError)
      delivery.stubs(:connection).returns(connection)
      delivery.expects(:reset_connection!).times(3)
      delivery.expects(:release_connection).once

      delivery.process!

      delivery.failure_count.should == 1
      delivery.success_count.should == 1
      delivery.total_count.should == 2
      written_messages.should == [@message2]
      exceptions.size.should == 3
      exceptions.first.is_a?(RuntimeError).should be_true
      failures.should == [@message1]
      read_exceptions.size.should == 4
    end

    it "invokes on_error callback if there are errors read" do
      messages = [@message1, @message2]
      written_messages = []
      exceptions = []
      failures = []
      read_exceptions = []
      errors = []
      callbacks = {
          :on_write => lambda { |d, m| written_messages << m },
          :on_exception => lambda { |d, e| exceptions << e },
          :on_failure => lambda { |d, m| failures << m },
          :on_read_exception => lambda { |d, e| read_exceptions << e },
          :on_error => lambda { |d, message_id, error_code| errors << [message_id, error_code] }
        }
      delivery = create_delivery(messages.dup, :callbacks => callbacks, :connection_config => @connection_config)

      connection = mock('connection')

      connection.expects(:next_message_id).returns(6)
      @message2.expects(:message_id=).with(6)
      @message1.expects(:message_id=).never

      apns = mock('apnsstr')
      @message2.stubs(:to_apns).returns(apns)

      connection.expects(:write).with(@message1.to_apns)
      connection.expects(:write).with(@message2.to_apns)
      selects = sequence('selects')
      connection.expects(:select).returns("something").in_sequence(selects)
      connection.expects(:select).returns(nil).in_sequence(selects)
      connection.expects(:read).returns("something")
      delivery.stubs(:connection).returns(connection)
      delivery.expects(:reset_connection!).times(1)
      delivery.expects(:release_connection).once

      delivery.process!

      delivery.failure_count.should == 1
      delivery.success_count.should == 1
      delivery.total_count.should == 2
      written_messages.should == [@message1, @message2]
      exceptions.size.should == 0
      failures.size.should == 0
      errors.should == [[1752458605, 111]]
    end
  end

  def create_delivery(messages, options = {})
    delivery = ApnClient::Delivery.new(messages, options)
    delivery.messages.should == messages
    delivery.callbacks.should == options[:callbacks]
    delivery.exception_count.should == 0
    delivery.success_count.should == 0
    delivery.failure_count.should == 0
    delivery.consecutive_failure_count.should == 0
    delivery.started_at.should be_nil
    delivery.finished_at.should be_nil
    delivery.elapsed.should == 0
    delivery.consecutive_failure_limit.should == 10
    delivery.exception_limit.should == 3
    delivery.sleep_on_exception.should == 1
    delivery
  end
end
