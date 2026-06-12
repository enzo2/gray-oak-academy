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

# SQL bind logging filters by column name, not nested JSON keys, so filter the
# whole JSONB settings column when it may contain credentials.
ActiveSupport.on_load(:active_record) do
  self.filter_attributes += [ /\Asettings\z/ ]
end
