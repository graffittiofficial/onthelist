require "digest"

module Admin
  class SessionsController < ApplicationController
    def new
    end

    def create
      if sign_in_throttled?
        return render_sign_in_throttled
      end

      admin_user = AdminUser.find_by(email: normalized_email)

      if admin_user&.authenticate(params[:password])
        return_to = session.delete(:admin_return_to)
        reset_session
        session[:admin_user_id] = admin_user.id
        Rails.cache.delete(account_attempt_key)
        redirect_to safe_return_path(return_to), notice: "Signed in."
      else
        record_failed_attempts
        flash.now[:alert] = "Email or password is incorrect."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      reset_session
      redirect_to new_admin_session_path, notice: "Signed out."
    end

    private

    def sign_in_throttled?
      [ ip_attempt_key, account_attempt_key ].any? do |key|
        Rails.cache.read(key).to_i >= failed_attempt_limit
      end
    end

    def record_failed_attempts
      [ ip_attempt_key, account_attempt_key ].each do |key|
        Rails.cache.increment(key, 1, expires_in: throttle_period)
      end
    end

    def render_sign_in_throttled
      flash.now[:alert] = "Too many sign-in attempts. Try again later."
      render :new, status: :too_many_requests
    end

    def safe_return_path(path)
      url_from(path) || admin_root_path
    end

    def failed_attempt_limit
      Rails.application.config.x.commerce.admin_authentication.fetch(:failed_attempt_limit)
    end

    def throttle_period
      Rails.application.config.x.commerce.admin_authentication.fetch(:throttle_period_seconds).seconds
    end

    def ip_attempt_key
      "admin-sign-in:ip:#{Digest::SHA256.hexdigest(request.remote_ip)}"
    end

    def account_attempt_key
      "admin-sign-in:account:#{Digest::SHA256.hexdigest(normalized_email)}"
    end

    def normalized_email
      params[:email].to_s.strip.downcase
    end
  end
end
