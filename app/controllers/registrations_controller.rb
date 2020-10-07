# frozen_string_literal: true

class RegistrationsController < ApplicationController
  def knock
    render json: {
      is_cryptchat: true
    }
  end

  def register
    if params[:id]
      verification_token, identity_key = params.require([:verification_token, :identity_key])
      record = Registration.find_by(id: params[:id])
      return render error_response(
        status: 404,
        message: I18n.t("registration_record_not_found")
      ) unless record

      result = record.verify(verification_token)
      if result[:success]
        user = User.new(
          country_code: record.country_code,
          phone_number: record.phone_number,
          identity_key: identity_key,
          instance_id: params[:instance_id]&.to_s
        )

        auth_token = nil
        ActiveRecord::Base.transaction do
          user.save!
          auth_token = AuthToken.generate(user)
          record.user_id = user.id
          record.save!
        end
        User.notify_users(excluded_user_id: user.id)
        render json: { id: user.id, auth_token: auth_token.unhashed_token, server_name: ServerSetting.server_name }
      else
        render error_response(
          status: 403,
          message: result[:reason]
        )
      end
    else
      country_code, phone_number = params.require([:country_code, :phone_number])
      record = Registration.find_or_initialize_by(country_code: country_code, phone_number: phone_number)
      if record && record.user_id.present?
        return render error_response(
          status: 403,
          message: I18n.t("number_already_registered")
        )
      end
      record.generate_token!
      if Rails.env.development? && ENV['SMS_STDOUT'].present?
        puts record.verification_token
      else
        SmsProviders.instance.send_sms(
          sms_content: I18n.t(
            "registration_sms_message",
            server_name: ServerSetting.server_name,
            code: record.verification_token,
            server_url: Rails.application.config.hostname
          ),
          to: country_code + phone_number
        )
      end
      render json: { id: record.id, sender_id: Rails.configuration.firebase[:sender_id] }
    end
  end
end
