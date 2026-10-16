module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin_user!

    private

    def authenticate_admin_user!
      return if current_admin_user

      session.delete(:admin_user_id)
      if request.get? && request.path != new_admin_session_path
        session[:admin_return_to] ||= request.fullpath
      end
      redirect_to new_admin_session_path, alert: "Sign in to continue."
    end

    def current_admin_user
      @current_admin_user ||= AdminUser.find_by(id: session[:admin_user_id])
    end
  end
end
