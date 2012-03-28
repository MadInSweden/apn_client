require 'rubygems'
require 'bundler/setup'

require 'apn_client'

RSpec.configure do |config|
  config.mock_with :mocha
end
