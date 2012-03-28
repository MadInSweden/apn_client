Dir[File.dirname(__FILE__) + "/apn_client/*.rb"].each do |file|
  require file
end
