#!/usr/bin/env ruby

require 'rubygems'

require 'openssl'
require 'base64'
require 'json'

# A response to a RightNet enrollment request containing the mapper's X509 cert,
# the instance (or other) agent's identity cert, and the agent's private key.
# Responses are encrypted using a secret key shared between the instance and
# the Certifying Authority (aka the RightScale core site) and integrity-protected
# using a similar key.
module RightScale

  class EnrollmentResult
    # Versions 5 and above use an identical format for the enrollment result
    SUPPORTED_VERSIONS = 5..AgentConfig.protocol_version
    
    class IntegrityFailure < Exception; end
    class VersionError < Exception; end

    attr_reader :r_s_version, :timestamp, :mapper_cert, :id_cert, :id_key

    # Create a new instance of this class
    #
    # === Parameters
    # timestamp(Time):: Timestamp associated with this result
    # mapper_cert(String):: Arbitrary string
    # id_cert(String):: Arbitrary string
    # id_key(String):: Arbitrary string
    # secret(String):: Shared secret with which the result is encrypted
    #
    def initialize(r_s_version, timestamp, mapper_cert, id_cert, id_key, secret)
      @r_s_version = r_s_version
      @timestamp   = timestamp.utc
      @mapper_cert = mapper_cert
      @id_cert     = id_cert
      @id_key      = id_key
      @serializer  = Serializer.new((:json if r_s_version < 12))

      msg = @serializer.dump({
        'mapper_cert' => @mapper_cert.to_s,
        'id_cert'     => @id_cert,
        'id_key'      => @id_key
      })

      key        = EnrollmentResult.derive_key(secret, @timestamp.to_i.to_s)
      #TODO switch to new OpenSSL API once we move to Ruby 1.8.7
      #cipher     = OpenSSL::Cipher.new("aes-256-cbc")
      cipher     = OpenSSL::Cipher::Cipher.new("aes-256-cbc")
      cipher.encrypt
      cipher.key = key
      cipher.iv = @iv = cipher.random_iv

      @ciphertext = cipher.update(msg) + cipher.final

      key   = EnrollmentResult.derive_key(secret.to_s.reverse, @timestamp.to_i.to_s)
      hmac   = OpenSSL::HMAC.new(key, OpenSSL::Digest::SHA1.new)
      hmac.update(@ciphertext)
      @mac  = hmac.digest
    end

    # Serialize an enrollment result
    #
    # === Parameters
    # obj(EnrollmentResult):: Object to serialize
    #
    # === Return
    # (String):: Serialized object
    #
    def to_s
      @serializer.dump({
          'r_s_version' => @r_s_version.to_s,
          'timestamp'   => @timestamp.to_i.to_s,
          'iv'          => Base64::encode64(@iv).chop,
          'ciphertext'  => Base64::encode64(@ciphertext).chop,
          'mac'         => Base64::encode64(@mac).chop
      })
    end

    # Compare this object to another one. Two results are equal if they have the same
    # payload (certs and keys) and timestamp. The crypto fields are not included in
    # the comparison because they are mutable.
    #
    # === Parameters
    # o(EnrollmentResult):: Object to compare against
    #
    # === Return
    # true|false:: Whether the objects' pertinent fields are identical
    #
    def ==(o)
      self.mapper_cert == o.mapper_cert &&
      self.id_cert == o.id_cert &&
      self.id_key == o.id_key &&
      self.timestamp.to_i == o.timestamp.to_i
    end

    # Serialize an enrollment result
    #
    # === Parameters
    # obj(EnrollmentResult):: Object to serialize
    #
    # === Return
    # (String):: Serialized object
    #
    def self.dump(obj)
      raise VersionError.new("Unsupported version #{obj.r_s_version}") unless SUPPORTED_VERSIONS.include?(obj.r_s_version)
      obj.to_s
    end

    # Unserialize the MessagePack encoded enrollment result
    #
    # === Parameters
    # string(String):: MessagePack representation of the result
    # secret(String):: Shared secret with which the result is encrypted
    #
    # === Return
    # result:: An instance of EnrollmentResult
    #
    # === Raise
    # IntegrityFailure:: if the message has been tampered with
    # VersionError:: if the specified protocol version is not locally supported
    #
    def self.load(string, secret)
      serializer = Serializer.new
      envelope = serializer.load(string)

      r_s_version = envelope['r_s_version'].to_i
      raise VersionError.new("Unsupported version #{r_s_version}") unless SUPPORTED_VERSIONS.include?(r_s_version)

      timestamp  = Time.at(envelope['timestamp'].to_i)
      iv         = Base64::decode64(envelope['iv'])
      ciphertext = Base64::decode64(envelope['ciphertext'])
      mac        = Base64::decode64(envelope['mac'])

      key        = self.derive_key(secret, timestamp.to_i.to_s)
      #TODO switch to new OpenSSL API once we move to Ruby 1.8.7
      #cipher     = OpenSSL::Cipher.new("aes-256-cbc")
      cipher     = OpenSSL::Cipher::Cipher.new("aes-256-cbc")
      cipher.decrypt
      cipher.key = key
      cipher.iv  = iv

      #TODO exclusively use new OpenSSL API (OpenSSL::CipherError) once we move to Ruby 1.8.7
      if defined?(OpenSSL::Cipher::CipherError)
        begin
          plaintext = cipher.update(ciphertext) + cipher.final
        rescue OpenSSL::Cipher::CipherError => e
          raise IntegrityFailure.new(e.message)
        end
      else
        begin
          plaintext = cipher.update(ciphertext) + cipher.final
        rescue OpenSSL::CipherError => e
          raise IntegrityFailure.new(e.message)
        end
      end

      key   = self.derive_key(secret.to_s.reverse, timestamp.to_i.to_s)
      hmac   = OpenSSL::HMAC.new(key, OpenSSL::Digest::SHA1.new)
      hmac.update(ciphertext)
      my_mac  = hmac.digest
      raise IntegrityFailure.new("MAC mismatch: expected #{my_mac}, got #{mac}") unless (mac == my_mac)

      msg = serializer.load(plaintext)
      mapper_cert = msg['mapper_cert']
      id_cert   = msg['id_cert']
      id_key    = msg['id_key']

      self.new(r_s_version, timestamp, mapper_cert, id_cert, id_key, secret)
    end

    protected

    def self.derive_key(secret, salt)
      begin
        return OpenSSL::PKCS5.pbkdf2_hmac_sha1(secret, salt, 2048, 32)
      rescue NameError => e
        return pkcs5_pbkdf2_hmac_sha1(secret, salt, 2048, 32)
      end
    end

    def self.pkcs5_pbkdf2_hmac_sha1(pass, salt, iter, len)
      ret = ''
      i = 0

      while len > 0
        i += 1
        hmac = OpenSSL::HMAC.new(pass, OpenSSL::Digest::SHA1.new)
        hmac.update(salt)
        hmac.update([i].pack('N'))
        digtmp = hmac.digest

        cplen = len > digtmp.length ? digtmp.length : len

        tmp = digtmp.dup

        1.upto(iter - 1) do |j|
          hmac = OpenSSL::HMAC.new(pass, OpenSSL::Digest::SHA1.new)
          hmac.update(digtmp)
          digtmp = hmac.digest
          0.upto(cplen - 1) do |k|
            tmp[k] = (tmp[k] ^ digtmp[k]).chr
          end
        end

        tmp.slice!((cplen)..-1) if (tmp.length > cplen)
        ret << tmp
        len -= tmp.length
      end

      ret
    end

  end
end
