# frozen_string_literal: true
class Registration < ApplicationRecord
  include HasPhoneNumber

  attr_accessor :verification_token

  belongs_to :user, optional: true

  validates :verification_token_hash, length: { is: 64 }
  validates :salt, length: { is: 32 }
  %i[verification_token_hash salt].each do |col|
    validates col, presence: true
  end

  def verify(verification_token)
    result = { success: true, reason: nil }
    if self.user_id.present?
      result[:success] = false
      result[:reason] = I18n.t("number_already_registered")
      return result
    end

    if self.created_at < 10.minutes.ago
      result[:success] = false
      result[:reason] = I18n.t("too_much_time_passed")
      return result
    end

    if !correct_token?(verification_token)
      result[:success] = false
      result[:reason] = I18n.t("incorrect_code")
    end
    result
  end

  def generate_token!
    verification_token, salt, hash = verification_data
    self.verification_token_hash = hash
    self.salt = salt
    self.created_at = self.updated_at = Time.zone.now
    self.save!
    self.verification_token = verification_token
  end

  private

  def verification_data
    verification_token = CryptUtilities.generate_digits_token(8)
    salt, hash = CryptUtilities.salt_and_hash(verification_token, Rails.configuration.token_pbkdf2_iterations)
    [verification_token, salt, hash]
  end

  def correct_token?(token)
    hashed_token = CryptUtilities.pbkdf2_hash(
      token,
      self.salt,
      Rails.configuration.token_pbkdf2_iterations
    )
    ActiveSupport::SecurityUtils.fixed_length_secure_compare(hashed_token, self.verification_token_hash)
  end
end

# == Schema Information
#
# Table name: registrations
#
#  id                      :bigint           not null, primary key
#  verification_token_hash :string(64)       not null
#  salt                    :string(32)       not null
#  country_code            :string(10)       not null
#  phone_number            :string(50)       not null
#  user_id                 :bigint
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_registrations_on_country_code_and_phone_number  (country_code,phone_number) UNIQUE
#
