module Admin
  class PickupLocationsController < BaseController
    before_action :set_pickup_location, only: %i[edit update]

    def index
      @pickup_locations = PickupLocation.order(:market_code, :name)
    end

    def new
      @pickup_location = PickupLocation.new(market_code: "US", country_code: "US", active: true)
    end

    def create
      @pickup_location = PickupLocation.new(pickup_location_params)

      if @pickup_location.save
        redirect_to admin_pickup_locations_path, notice: "Pickup location saved."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @pickup_location.update(pickup_location_params)
        redirect_to admin_pickup_locations_path, notice: "Pickup location saved."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_pickup_location
      @pickup_location = PickupLocation.find(params[:id])
    end

    def pickup_location_params
      params.require(:pickup_location).permit(
        :name, :market_code, :address_line1, :address_line2, :city, :state, :postal_code, :country_code, :active
      )
    end
  end
end
