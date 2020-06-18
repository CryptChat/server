# frozen_string_literal: true

class EphemeralKeysController < ApplicationController
  before_action :ensure_logged_in

  def top_up
    keys = params.permit([{ keys: [:id, :key] }])[:keys]
    if !(Array === keys) || keys.size == 0
      return render json: { messages: [I18n.t("keys_param_incorrect_format")] }, status: 422
    end
    keys.each do |k|
      k.require(%i[id key])
    end

    user = current_user
    count = user.ephemeral_keys.count
    if count + keys.size > Rails.configuration.user_ephemeral_keys_max_count
      return render json: { messages: [I18n.t("keys_count_exceeds_limit")] }, status: 403
    end

    user.add_ephemeral_keys!(keys)
    render json: {}, status: 200
  end

  def grab
    user = User.find_by(id: params.require(:user_id))
    return render json: {}, status: 404 unless user

    key = user.atomic_delete_and_return_ephemeral_key!
    render json: (key || {})
  end
end
