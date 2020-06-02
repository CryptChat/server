# frozen_string_literal: true

require 'test_helper'

class MessagesControllerTest < ActionDispatch::IntegrationTest
  test "#transmit requires body, mac, iv and receiver_user_id" do
    sender = Fabricate(:user)
    receiver = Fabricate(:user)

    post "/message.json", params: { message: {} }
    assert_equal(400, response.status)
    error_message = "param is missing or the value is empty: "
    assert_equal(error_message + "message", response.parsed_body["messages"].first)

    message_params = {
      body: "this is my encrypted secret message",
      mac: SecureRandom.hex,
      iv: SecureRandom.hex,
      receiver_user_id: receiver.id,
      sender_user_id: sender.id
    }
    %i[body mac iv receiver_user_id].each do |param|
      post "/message.json", params: { message: message_params.slice(*(message_params.keys - [param])) }
      assert_equal(400, response.status)
      assert_equal(error_message + param.to_s, response.parsed_body["messages"].first)
    end
  end

  test "#transmit creates message" do
    sender = Fabricate(:user)
    receiver = Fabricate(:user)
    message_params = {
      body: "this is my encrypted secret message",
      mac: SecureRandom.hex,
      iv: SecureRandom.hex,
      receiver_user_id: receiver.id,
      sender_user_id: sender.id
    }
    stub_firebase(receiver)
    post "/message.json", params: { message: message_params }
    assert_equal(200, response.status)
    message = Message.find(response.parsed_body["message"]["id"])
    assert_equal(message_params[:body], message.body)
    assert_equal(message_params[:mac], message.mac)
    assert_equal(message_params[:iv], message.iv)
    assert_equal(message_params[:receiver_user_id], message.receiver_user_id)
    assert_equal(message_params[:sender_user_id], message.sender_user_id)
  end

  test '#transmit optional params must be all present or none' do
    sender = Fabricate(:user)
    receiver = Fabricate(:user)
    message_params = {
      body: "this is my encrypted secret message",
      mac: SecureRandom.hex,
      iv: SecureRandom.hex,
      receiver_user_id: receiver.id,
      sender_user_id: sender.id
    }
    post "/message.json", params: {
      message: message_params.merge(sender_ephemeral_public_key: "pubkey")
    }
    assert_equal(422, response.status)
    assert_equal(I18n.t("sepk_present_but_not_ekioud"), response.parsed_body["messages"].first)

    post "/message.json", params: { 
      message: message_params.merge(ephemeral_key_id_on_user_device: 11)
    }
    assert_equal(422, response.status)
    assert_equal(I18n.t("ekioud_present_but_not_sepk"), response.parsed_body["messages"].first)

    stub_firebase(receiver)
    post "/message.json", params: { 
      message: message_params.merge(
        sender_ephemeral_public_key: "pubkey",
        ephemeral_key_id_on_user_device: 11
      )
    }
    assert_equal(200, response.status)
    message = Message.find(response.parsed_body["message"]["id"])
    assert_equal(message_params[:body], message.body)
    assert_equal("pubkey", message.sender_ephemeral_public_key)
    assert_equal(11, message.ephemeral_key_id_on_user_device)
  end

  test '#sync returns messages for current user' do
    current_user = Fabricate(:user)
    sender1 = Fabricate(:user)
    sender2 = Fabricate(:user)

    msg1 = Fabricate(:message, sender_user_id: sender1.id, receiver_user_id: current_user.id)
    msg2 = Fabricate(:message, sender_user_id: sender2.id, receiver_user_id: current_user.id)
    msg3 = Fabricate(:message, sender_user_id: sender2.id, receiver_user_id: current_user.id)
    msg4 = Fabricate(:message, sender_user_id: sender1.id, receiver_user_id: current_user.id)
    msg5 = Fabricate(:message, sender_user_id: current_user.id, receiver_user_id: sender1.id)

    get '/sync/messages.json', params: { user_id: current_user.id }
    assert_equal(200, response.status)
    assert_equal([msg1, msg2, msg3, msg4].map(&:id), response.parsed_body["messages"].map { |m| m["id"] })

    get '/sync/messages.json', params: { user_id: current_user.id, last_seen_id: msg2.id }
    assert_equal(200, response.status)
    assert_equal([msg3, msg4].map(&:id), response.parsed_body["messages"].map { |m| m["id"] })
  end

  private

  def stub_firebase(receiver)
    stub_request(:post, Notifier::FIREBASE_API_URI.to_s).with(
      body: {
        registration_ids: [receiver.instance_id],
        data: { command: "sync_messages" }
      }.to_json,
      headers: {
        "Content-Type" => "application/json",
        "Authorization" => "key=someserverkeygoesinheretestenv" # From Rails.configuration.firebase[:server_key]
      }
    )
  end
end
