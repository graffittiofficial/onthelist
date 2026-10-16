module Admin
  class ProductImagesController < BaseController
    before_action :set_product
    before_action :set_product_image, only: %i[update destroy move_up move_down]

    def create
      saved = false
      @product.with_lock do
        @product_image = @product.product_images.build(product_image_params)
        saved = @product_image.save
      end

      if saved
        redirect_to edit_admin_product_path(@product), notice: "Product image added."
      else
        redirect_to edit_admin_product_path(@product), alert: @product_image.errors.full_messages.to_sentence
      end
    end

    def update
      if @product_image.update(product_image_params)
        redirect_to edit_admin_product_path(@product), notice: "Image description saved."
      else
        redirect_to edit_admin_product_path(@product), alert: @product_image.errors.full_messages.to_sentence
      end
    end

    def destroy
      @product.with_lock do
        removed_position = @product_image.position
        @product_image.destroy!
        @product.product_images.where("position > ?", removed_position).order(:position).each do |image|
          image.update!(position: image.position - 1)
        end
      end
      redirect_to edit_admin_product_path(@product), notice: "Product image removed."
    end

    def move_up
      move_image(-1)
    end

    def move_down
      move_image(1)
    end

    private

    def set_product
      @product = Product.find(params[:product_id])
    end

    def set_product_image
      @product_image = @product.product_images.find(params[:id])
    end

    def product_image_params
      params.require(:product_image).permit(:image, :alt_text)
    end

    def move_image(direction)
      @product.with_lock do
        adjacent_image = @product.product_images.find_by(position: @product_image.position + direction)
        if adjacent_image
          current_position = @product_image.position
          adjacent_position = adjacent_image.position
          @product_image.update_column(:position, -1)
          adjacent_image.update!(position: current_position)
          @product_image.update!(position: adjacent_position)
        end
      end
      redirect_to edit_admin_product_path(@product), notice: "Product image order updated."
    end
  end
end
