# APN Client RubyGem

## Introduction

This is a RubyGem that allows sending of Apple Push Notifications to iOS devices (i.e. iPhones, iPads) from Ruby. The main features are:

* Efficient broadcasting of notifications to a large number of devices in a reliable fashion.
* Dealing with errors (via the enhanced format Apple protocol) and make sure every deliverable message gets delivered.

## Fork note
Please note that in this forked version (version numers suffixed with .footballaddicts) we've changed the syntax for most things, and the code has undergone an almost complete rewrite.

One of the larger internal changes we've done is refactoring payload creation to a separate class (ApnClient::Payload). We've done this in order to reuse the cpu-expensive part of the message for multiple messages. It is an absolutly essential part of sending tens of thousands of messages *fast*.

We've also added support for an optional, externaly defined, ConnectionPool (basicly an object supporting #push and #pop that's preloaded with a bunch of ApnClient::Connection instances).

## Usage

### Delivering Your Messages

This example uses a minimum of optional parameters, for deeper API introduction – see the api docs.

```
require 'apn_client'

payload = ApnClient::Payload.new(:alert => "Test message!")
messages = []
messages << ApnClient::Message.new("7b7b8de5888bb742ba744a2a5c8e52c6481d1deeecc283e830533b7c6bf1d099", payload)
messages << ApnClient::Message.new("6a5d8de123923912ba744a2a238203aef82d1d98eac283e830533b7c6bf1a100", payload)
options  = { :connection_config => { :host => 'gateway.push.apple.com', :cert => IO.read("my_apn_certificate.pem") } }
delivery = ApnClient::Delivery.new(messages,options)

begin
    delivery.process!
    puts "Delivered successfully!"
rescue ExceptionLimitReached
    puts "Failed to deliver."
end
```

### Checking for Feedback

This will probably be included in a future release.

## Dependencies

The payload of an APN message is a JSON formated hash (containing alert message, badge count, content available etc.) and therefore a JSON library needs to be present. We're depending on "yajl-ruby" to encode our JSON.

The gem is tested on MRI 1.9.2 and MRI 1.9.3.

## Credits
[Football Addicts](http://www.footballaddicts.com/our-apps/index.html) has made major changes to this fork of the gem, which is now starting to look more like a rewrite.

The original gem was created by [Peter Marklund](git://github.com/peter/apn_client.git).

### Original gem credits:
This gem is an extraction of production code at [Mag+](http://www.magplus.com) and both [Dennis Rogenius](https://github.com/denro) and [Lennart Friden](https://github.com/DevL) made important contributions along the way.

The APN connection code has its origins in the [APN on Rails](https://github.com/jwang/apn_on_rails) gem.

## License

This library is released under the MIT license.

## Resources

* [Apple Push Notifications Documentation](http://developer.apple.com/library/ios/#documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Introduction/Introduction.html#//apple_ref/doc/uid/TP40008194-CH1-SW1)
