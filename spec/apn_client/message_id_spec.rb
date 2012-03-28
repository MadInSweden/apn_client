require 'spec_helper'

describe ApnClient::MessageId do

  context '.next' do
    it "should return consequtive messages" do
      i = 1000

      subject.instance_variable_set(:'@message_id', i)
      1000.times { subject.next.should == (i+=1) }
    end


    it "should wrap to message_id 1 at message_id = (1 << 4*8)" do
      subject.instance_variable_set(:'@message_id', (1 << 4*8) - 2)

      subject.next.should == ((1 << 4*8) - 1)
      subject.next.should == 1
      subject.next.should == 2
    end

    it "should start at 1" do
      subject.instance_variable_set(:'@message_id', nil)

      subject.next.should == 1
      subject.next.should == 2
      subject.next.should == 3
    end

    it "should be thread safe" do
      mutex = Mutex.new
      found = []
      subject.instance_variable_set(:'@message_id', nil)

      threads = 10.times.map do
        Thread.new do
          10.times { n = subject.next; sleep(rand()*0.01); mutex.synchronize { found << n } }
        end
      end
      threads.each(&:join)

      # Should be out of order
      found.should_not == 1.upto(100).to_a

      # Should contain everything
      1.upto(100) { |n| found.should include(n) }
      found.size.should == 100
    end

  end

end
