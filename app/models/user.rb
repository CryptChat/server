# frozen_string_literal: true

class User < ApplicationRecord
  include HasPhoneNumber

  has_many :received_messages, foreign_key: :receiver_user_id, class_name: 'Message'
  has_many :sent_messages, foreign_key: :sender_user_id, class_name: 'Message'
  has_many :ephemeral_keys

  has_one :registration

  validates :name, length: { maximum: 255 }

  def atomic_delete_and_return_ephemeral_key!
    arg = Rails.env.test? ? {} : { isolation: :serializable }
    query = <<~SQL
      DELETE FROM ephemeral_keys
      WHERE id = (
        SELECT id
        FROM ephemeral_keys
        WHERE user_id = ?
        LIMIT 1
      )
      RETURNING *
    SQL
    User.transaction(**arg) do
      EphemeralKey.find_by_sql([query, self.id]).first
    end
  end

  def add_ephemeral_keys!(keys)
    mapped = keys.map do |key|
      timestamp = Time.zone.now
      {
        key: key[:key],
        id_on_user_device: key[:id],
        user_id: self.id,
        created_at: timestamp,
        updated_at: timestamp
      }
    end
    self.ephemeral_keys.insert_all(mapped)
  end
end

# == Schema Information
#
# Table name: users
#
#  id           :bigint           not null, primary key
#  name         :string(255)
#  country_code :string(10)       not null
#  phone_number :string(50)       not null
#  instance_id  :string
#  identity_key :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_users_on_country_code_and_phone_number  (country_code,phone_number) UNIQUE
#  index_users_on_identity_key                   (identity_key) UNIQUE
#  index_users_on_instance_id                    (instance_id) UNIQUE
#
