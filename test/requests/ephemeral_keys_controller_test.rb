# frozen_string_literal: true
require 'test_helper'

class EphemeralKeysControllerTest < ActionDispatch::IntegrationTest
  test '#top_up complains when no keys param is given' do
    user = Fabricate(:user)
    post '/ephemeral-keys.json', params: { user_id: user.id }
    assert_equal(422, response.status)
    assert_equal(I18n.t("keys_param_incorrect_format"), response.parsed_body["messages"].first)
  end

  test '#top_up complains when keys param is not an array' do
    user = Fabricate(:user)
    post '/ephemeral-keys.json', params: { user_id: user.id, keys: "dsa" }
    assert_equal(422, response.status)
    assert_equal(I18n.t("keys_param_incorrect_format"), response.parsed_body["messages"].first)
  end

  test '#top_up complains when given too many keys' do
    user = Fabricate(:user)
    keys = (1..15).map { |n| { id: n, key: "key#{n}" } }
    post '/ephemeral-keys.json', params: { user_id: user.id, keys: keys }
    assert_equal(403, response.status)
    assert_equal(I18n.t("keys_count_exceeds_limit"), response.parsed_body["messages"].first)

    keys = (1..5).map { |n| { id: n, key: "key#{n}" } }
    post '/ephemeral-keys.json', params: { user_id: user.id, keys: keys }
    assert_equal(200, response.status)
    assert_equal(keys, formatted_ephemeral_keys(user))

    keys2 = (6..20).map { |n| { id: n, key: "key#{n}" } }
    post '/ephemeral-keys.json', params: { user_id: user.id, keys: keys2 }
    assert_equal(403, response.status)
    assert_equal(I18n.t("keys_count_exceeds_limit"), response.parsed_body["messages"].first)
    assert_equal(keys, formatted_ephemeral_keys(user))
  end

  test '#top_up adds keys' do
    user = Fabricate(:user)
    keys = (1..5).map { |n| { id: n, key: "key#{n}" } }
    post '/ephemeral-keys.json', params: { user_id: user.id, keys: keys }
    assert_equal(200, response.status)
    assert_equal(keys, formatted_ephemeral_keys(user))

    keys2 = (6..9).map { |n| { id: n, key: "key#{n}" } }
    post '/ephemeral-keys.json', params: { user_id: user.id, keys: keys2 }
    assert_equal(200, response.status)
    assert_equal( keys + keys2, formatted_ephemeral_keys(user))
  end

  private

  def formatted_ephemeral_keys(user)
    user.ephemeral_keys.pluck(:id_on_user_device, :key)
      .map { |k| { id: k[0], key: k[1] } }
      .sort_by { |k| k[:key] }
  end
end
