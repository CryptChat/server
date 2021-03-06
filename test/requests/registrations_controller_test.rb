# frozen_string_literal: true
require 'test_helper'

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "#knock should salute you" do
    get "/knock-knock.json"
    assert_equal(200, response.status)
    json = JSON.parse(response.body)
    assert_equal(true, json["is_cryptchat"])
  end

  test "#register requires country_code and phone_number when id is absent" do
    post "/register.json", params: { phone_number: "111" }
    assert_equal(400, response.status)
    assert_includes(response.parsed_body["messages"], "param is missing or the value is empty: country_code")

    post "/register.json", params: { country_code: "111" }
    assert_equal(400, response.status)
    assert_includes(response.parsed_body["messages"], "param is missing or the value is empty: phone_number")
  end

  test "#register without id param creates a registration record" do
    stub_request(:post, "https://api.twilio.com/2010-04-01/Accounts/AC61e2c567d230b0c0c60345622e583008/Messages.json")
      .with(
        body: {
          'Body' => i18n_sms("12345678"),
          'From' => '+966501234567',
          'To' => '1111111'
        },
        headers: {
          'Authorization' => 'Basic QUM2MWUyYzU2N2QyMzBiMGMwYzYwMzQ1NjIyZTU4MzAwODo1NGM0YjVjYmYzNGFjYmY3YTljNWU3MzQ3Y2IwN2Q0NQ==',
        }
      )
      .to_return(status: 200, body: "", headers: {})
    SecureRandom.stub :rand, 0.123456789123456789 do
      post "/register.json", params: { country_code: "111", phone_number: "1111" }
    end
    assert_equal(200, response.status)
    id = response.parsed_body["id"]
    record = Registration.find(id)
    assert_equal("1111", record.phone_number)
    assert_equal("111", record.country_code)
    assert_equal("53042389432432", response.parsed_body["sender_id"]) # From Rails.configuration.firebase[:sender_id]
    assert_nil(record.user_id)
  end

  test "#register without id param doesn't create registration if number already exists on the system" do
    user = Fabricate(:user)
    Fabricate(:registration,
      phone_number: user.phone_number,
      country_code: user.country_code,
      user_id: user.id
    )

    post "/register.json", params: { country_code: user.country_code, phone_number: user.phone_number }
    assert_equal(403, response.status)
    assert_includes(response.parsed_body["messages"], I18n.t("number_already_registered"))
  end

  test "#register resets token and timestamps if record already exists but not confirmed" do
    stub_request(:post, "https://api.twilio.com/2010-04-01/Accounts/AC61e2c567d230b0c0c60345622e583008/Messages.json")
      .with(
        body: {
          'Body' => i18n_sms("12345678"),
          'From' => '+966501234567',
          'To' => '1111111'
        },
        headers: {
          'Authorization' => 'Basic QUM2MWUyYzU2N2QyMzBiMGMwYzYwMzQ1NjIyZTU4MzAwODo1NGM0YjVjYmYzNGFjYmY3YTljNWU3MzQ3Y2IwN2Q0NQ==',
        }
      )
      .to_return(status: 200, body: "", headers: {})

    SecureRandom.stub :rand, 0.123456789123456789 do
      post "/register.json", params: { country_code: "111", phone_number: "1111" }
    end
    assert_equal(200, response.status)
    record = Registration.find(response.parsed_body["id"])

    travel(5.minutes)

    SecureRandom.stub :rand, 0.123456789123456789 do
      post "/register.json", params: { country_code: "111", phone_number: "1111" }
    end
    assert_equal(200, response.status)
    new_record = Registration.find(response.parsed_body["id"])

    assert_not_equal(record.verification_token_hash, new_record.verification_token_hash)
    assert_not_equal(record.salt, new_record.salt)
    assert_equal(record.id, new_record.id)
    assert_in_delta(new_record.created_at - record.created_at, 5 * 60, 1)
    assert_nil(record.user_id)
    assert_nil(new_record.user_id)
  end

  test "#register doesn't reset token if registration is confirmed" do
    notified_users = [Fabricate(:user), Fabricate(:user)].sort_by(&:id)
    Fabricate(:user, suspended: true) # not notified

    stub_request(:post, "https://api.twilio.com/2010-04-01/Accounts/AC61e2c567d230b0c0c60345622e583008/Messages.json")
      .with(
        body: {
          'Body' => i18n_sms("12345678"),
          'From' => '+966501234567',
          'To' => '1111111'
        },
        headers: {
          'Authorization' => 'Basic QUM2MWUyYzU2N2QyMzBiMGMwYzYwMzQ1NjIyZTU4MzAwODo1NGM0YjVjYmYzNGFjYmY3YTljNWU3MzQ3Y2IwN2Q0NQ==',
        }
      )
      .to_return(status: 200, body: "", headers: {})

    SecureRandom.stub :rand, 0.123456789123456789 do
      post "/register.json", params: { country_code: "111", phone_number: "1111" }
    end
    assert_equal(200, response.status)
    record = Registration.find(response.parsed_body["id"])
    assert_nil(record.user_id)

    ServerSetting.server_name = 'small test server'
    stub_firebase(
      notified_users,
      data: { command: Notifier::SYNC_USERS_COMMAND }
    )
    post "/register.json", params: {
      id: record.id,
      verification_token: "12345678",
      identity_key: "3333aaaa",
      instance_id: "dfwersadsad"
    }
    assert_equal(400, response.status)
    post "/register.json", params: {
      id: record.id,
      verification_token: "12345678",
      identity_key: "3333aaaa",
      instance_id: "dfwersadsad",
      country_code: "111",
      phone_number: "11111" # wrong number
    }
    assert_equal(404, response.status)
    post "/register.json", params: {
      id: record.id,
      verification_token: "12345678",
      identity_key: "3333aaaa",
      instance_id: "dfwersadsad",
      country_code: "111",
      phone_number: "1111"
    }
    assert_equal(200, response.status)
    assert_equal(32, response.parsed_body["auth_token"].size)
    assert_equal('small test server', response.parsed_body["server_name"])
    record.reload
    assert(record.user)
    assert_equal(record.user.id, response.parsed_body["id"])
    assert_equal(record.user.phone_number, record.phone_number)
    assert_equal(record.user.country_code, record.country_code)
    assert_equal("dfwersadsad", record.user.instance_id)
    old_attrs = record.attributes

    travel(5.minutes)

    post "/register.json", params: {
      id: record.id,
      verification_token: "12345678",
      identity_key: "4444bbbb",
      country_code: "111",
      phone_number: "1111"
    }
    assert_equal(403, response.status)
    assert_includes(response.parsed_body["messages"], I18n.t("number_already_registered"))
    record.reload
    assert_equal(old_attrs, record.attributes)
  end

  test "#register doesn't confirm registration if incorrect token is provided" do
    stub_request(:post, "https://api.twilio.com/2010-04-01/Accounts/AC61e2c567d230b0c0c60345622e583008/Messages.json")
      .with(
        body: {
          'Body' => i18n_sms("12345678"),
          'From' => '+966501234567',
          'To' => '1111111'
        },
        headers: {
          'Authorization' => 'Basic QUM2MWUyYzU2N2QyMzBiMGMwYzYwMzQ1NjIyZTU4MzAwODo1NGM0YjVjYmYzNGFjYmY3YTljNWU3MzQ3Y2IwN2Q0NQ==',
        }
      )
      .to_return(status: 200, body: "", headers: {})
    SecureRandom.stub :rand, 0.123456789123456789 do
      post "/register.json", params: { country_code: "111", phone_number: "1111" }
    end
    assert_equal(200, response.status)
    record = Registration.find(response.parsed_body["id"])
    assert_nil(record.user_id)

    post "/register.json", params: {
      id: record.id,
      verification_token: "aaaabbbb",
      identity_key: "3333aaaa",
      country_code: "111",
      phone_number: "1111"
    }
    assert_equal(403, response.status)
    assert_includes(response.parsed_body["messages"], I18n.t("incorrect_code"))
    record.reload
    assert_nil(record.user_id)
  end

  test "#register doesn't confirm registration if too much time has passed" do
    stub_request(:post, "https://api.twilio.com/2010-04-01/Accounts/AC61e2c567d230b0c0c60345622e583008/Messages.json")
      .with(
        body: {
          'Body' => i18n_sms("12345678"),
          'From' => '+966501234567',
          'To' => '1111111'
        },
        headers: {
          'Authorization' => 'Basic QUM2MWUyYzU2N2QyMzBiMGMwYzYwMzQ1NjIyZTU4MzAwODo1NGM0YjVjYmYzNGFjYmY3YTljNWU3MzQ3Y2IwN2Q0NQ==',
        }
      )
      .to_return(status: 200, body: "", headers: {})

    SecureRandom.stub :rand, 0.123456789123456789 do
      post "/register.json", params: { country_code: "111", phone_number: "1111" }
    end
    assert_equal(200, response.status)
    record = Registration.find(response.parsed_body["id"])
    assert_nil(record.user_id)

    travel(20.minutes)

    post "/register.json", params: {
      id: record.id,
      verification_token: "12345678",
      identity_key: "3333aaaa",
      country_code: "111",
      phone_number: "1111"
    }
    assert_equal(403, response.status)
    assert_includes(response.parsed_body["messages"], I18n.t("too_much_time_passed"))
    record.reload
    assert_nil(record.user_id)
  end

  test '#register rejects registrations if the server is invite only and no invite exists for the phone number' do
    ServerSetting.invite_only = true
    invite = Fabricate(:invite, country_code: '+966', phone_number: '123469', expires_at: 15.minutes.from_now)
    post "/register.json", params: { country_code: "111", phone_number: "1111" }
    assert_equal(403, response.status)
    assert_equal(I18n.t("registration_invite_only"), response.parsed_body["messages"].first)
    refute(invite.reload.claimed?)

    stub_request(:post, "https://api.twilio.com/2010-04-01/Accounts/AC61e2c567d230b0c0c60345622e583008/Messages.json")
      .with(
        body: {
          'Body' => i18n_sms("12345678"),
          'From' => '+966501234567',
          'To' => '+966123469'
        },
        headers: {
          'Authorization' => 'Basic QUM2MWUyYzU2N2QyMzBiMGMwYzYwMzQ1NjIyZTU4MzAwODo1NGM0YjVjYmYzNGFjYmY3YTljNWU3MzQ3Y2IwN2Q0NQ==',
        }
      )
      .to_return(status: 200, body: "", headers: {})
    SecureRandom.stub :rand, 0.123456789123456789 do
      post "/register.json", params: { country_code: '+966', phone_number: '123469' }
    end
    assert_equal(200, response.status)
    refute(invite.reload.claimed?)

    id = response.parsed_body["id"]
    travel(25.minutes) do
      post "/register.json", params: {
        id: id,
        verification_token: "12345678",
        identity_key: "3333aaaa",
        country_code: '+966',
        phone_number: '123469'
      }
    end
    assert_equal(403, response.status)
    assert_equal(I18n.t("registration_invite_expired"), response.parsed_body["messages"].first)
    refute(invite.reload.claimed?)

    stub_firebase(
      User.all.to_a,
      data: { command: Notifier::SYNC_USERS_COMMAND }
    )
    post "/register.json", params: {
      id: id,
      verification_token: "12345678",
      identity_key: "3333aaaa",
      country_code: '+966',
      phone_number: '123469'
    }
    assert_equal(200, response.status)
    assert_equal(32, response.parsed_body["auth_token"].size)
    assert(invite.reload.claimed?)
    attrs = invite.attributes

    post "/register.json", params: { country_code: '+966', phone_number: '123469' }
    assert_equal(403, response.status)
    assert_equal(I18n.t("registration_invite_only"), response.parsed_body["messages"].first)

    post "/register.json", params: {
      id: id,
      verification_token: "12345678",
      identity_key: "3333aaaa",
      country_code: '+966',
      phone_number: '123469'
    }
    assert_equal(403, response.status)
    assert_equal(I18n.t("registration_invite_only"), response.parsed_body["messages"].first)
    assert_equal(attrs, invite.reload.attributes)
  end

  private

  def i18n_sms(code)
    I18n.t(
      "registration_sms_message",
      server_name: ServerSetting.server_name,
      token: code,
      server_url: Rails.application.config.hostname
    )
  end
end
