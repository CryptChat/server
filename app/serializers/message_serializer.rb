# frozen_string_literal: true

class MessageSerializer < ActiveModel::Serializer
  attributes(
    :id,
    :body,
    :mac,
    :iv,
    :sender_user_id,
    :sender_ephemeral_public_key,
    :ephemeral_key_id_on_user_device,
    :created_at
  )

  def created_at
    (object.created_at.to_f * 1000).floor
  end
end

# == Schema Information
#
# Table name: messages
#
#  id                              :bigint           not null, primary key
#  body                            :text             not null
#  mac                             :text             not null
#  iv                              :text             not null
#  sender_user_id                  :bigint           not null
#  receiver_user_id                :bigint           not null
#  sender_ephemeral_public_key     :text
#  ephemeral_key_id_on_user_device :bigint
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#
