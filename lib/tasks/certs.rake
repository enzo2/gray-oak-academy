# filepath: /workspaces/gray-oak-academy/lib/tasks/certs.rake
require "fileutils"

namespace :certs do
  desc "Generate self-signed SSL certificate and keys for the provided hostname (defaults to localhost)"
  task :generate, [ :hostname ] do |_t, args|
    hostname = args[:hostname] || "localhost"
    puts "\n== Generating SSL certificate for #{hostname} =="

    cert_path = Rails.root.join("config", "certs")
    FileUtils.mkdir_p(cert_path)

    root_key_path = cert_path.join("root-ca.key")
    root_cert_path = cert_path.join("root-ca.crt")
    server_key_path = cert_path.join("#{hostname}.key")
    server_cert_path = cert_path.join("#{hostname}.crt")
    server_csr_path = cert_path.join("#{hostname}.csr")
    extfile_path = cert_path.join("#{hostname}.ss.cnf")

    begin
      # Generate Root CA if it doesn't exist
      unless File.exist?(root_cert_path)
        puts "Generating Root CA..."
        system(
          "openssl req -x509 -nodes -newkey RSA:2048 " \
          "-keyout #{root_key_path} -days 365 -out #{root_cert_path} " \
          "-subj '/C=US/ST=Denial/L=Earth/O=Private Certificate Authority/CN=Root CA for Local Certificates'",
          exception: true
        )
      else
        puts "Root CA already exists."
      end

      # Generate Server Certificate if it doesn't exist
      unless File.exist?(server_cert_path) && File.exist?(server_key_path)
        puts "Generating Server Certificate for #{hostname}..."
        # Generate server key and CSR
        system(
          "openssl req -nodes -newkey rsa:2048 " \
          "-keyout #{server_key_path} -out #{server_csr_path} " \
          "-subj '/C=US/ST=Denial/L=Earth/O=Dis/CN=#{hostname}'",
          exception: true
        )

        # Create extension file
        File.write(extfile_path, <<~CONF)
          subjectAltName = DNS:#{hostname}
          authorityKeyIdentifier = keyid,issuer
          basicConstraints = CA:FALSE
          keyUsage = digitalSignature, keyEncipherment
          extendedKeyUsage=serverAuth
        CONF

        # Sign the server certificate with the Root CA
        system(
          "openssl x509 -req -CA #{root_cert_path} -CAkey #{root_key_path} " \
          "-in #{server_csr_path} -out #{server_cert_path} " \
          "-days 365 -CAcreateserial -extfile #{extfile_path}",
          exception: true
        )
        puts "Server certificate generated."
      else
        puts "Server certificate already exists."
      end

      puts "Certificate generation complete."
      puts "Root CA: #{root_cert_path}"
      puts "Server Cert: #{server_cert_path}"
      puts "Server Key: #{server_key_path}"

    rescue => e
      puts "Error generating certificates: #{e.message}"
      # Optionally re-raise or exit
      # raise e
      exit(1)
    ensure
      # Clean up temporary files
      FileUtils.rm_f(server_csr_path)
      FileUtils.rm_f(extfile_path)
      FileUtils.rm_f(cert_path.join("root-ca.srl")) # remove serial file if created
    end
  end
end
