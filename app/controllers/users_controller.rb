# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :ensure_logged_in

  def sync
    # updated_at param unit is ms since epoch
    updated_at = params[:updated_at]&.to_i || 0
    users = User.where("FLOOR(EXTRACT(EPOCH FROM updated_at) * 1000) > ? AND id <> ?", updated_at, current_user.id)
    render json: users
  end

  def update
    user = current_user
    new_attrs = user_params
    if name = new_attrs[:name]
      new_attrs[:name] = name.strip
    end
    if user.update(new_attrs)
      User.notify_users(excluded_user_id: user.id)
      render success_response
    else
      render error_response(
        status: 422,
        messages: user.errors.full_messages
      )
    end
  end

  private

  # Only allow a trusted parameter "white list" through.
  def user_params
    params.require(:user).permit(
      :country_code,
      :phone_number,
      :instance_id,
      :name
    )
  end
end
