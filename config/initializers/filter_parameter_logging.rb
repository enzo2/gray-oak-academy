# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.


Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :_key, :crypt, :salt, :certificate, :otp, :ssn
  # removed :token to avoid filtering out "tokens" as well
]

 # Can use if you want to filter out "token" but not "tokens"
 Rails.application.config.filter_parameters += [
  lambda do |key, value|
   key.to_s =~ /\A(.*)token(?!s)(.*)\z/i
  end
 ]

# workaround due to bug, filtering doesn't work on SQL logging within a hash, so filter out the whole parameter containing the hash
ActiveRecord::Base.filter_attributes += [ :settings ]
