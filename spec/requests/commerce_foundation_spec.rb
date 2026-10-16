require "rails_helper"

RSpec.describe "Commerce foundation", type: :request do
  def post_admin_session(params)
    get new_admin_session_path
    token = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')&.[]("value")
    post admin_session_path, params: params.merge(authenticity_token: token)
  end

  def request_csrf_token
    Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')&.[]("value")
  end

  def normalized_auth_error_response
    document = Nokogiri::HTML(response.body)
    document.css('meta[name="csrf-token"], input[name="authenticity_token"]').remove
    [ response.status, document.to_html ]
  end

  describe "storefront" do
    it "renders the home page" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Fashion, on the list")
    end

    describe "Cart and Stripe payments" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("STRIPE_WEBHOOK_SECRET").and_return("whsec_test")
        allow(ENV).to receive(:[]).with("STRIPE_PUBLISHABLE_KEY").and_return("pk_test_fake")
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("STRIPE_SECRET_KEY").and_return("sk_test_fake")
        allow(ENV).to receive(:fetch).with("STRIPE_PUBLISHABLE_KEY").and_return("pk_test_fake")
      end

      let!(:pickup_location) do
        PickupLocation.create!(
          name: "Main store",
          market_code: "US",
          address_line1: "10 Market Street",
          city: "San Francisco",
          state: "CA",
          postal_code: "94105",
          country_code: "US"
        )
      end
      let!(:product) do
        Product.create!(slug: "cart-shirt", status: "published").tap do |record|
          record.translations.create!(locale: "en", name: "Cart shirt")
        end
      end
      let!(:variant) do
        product.variants.create!(sku: "CART-S", size: "S", color: "Black", stock_quantity: 4).tap do |record|
          record.prices.create!(currency: "USD", amount_cents: 5_000)
        end
      end

      def add_variant_to_cart(quantity: 1)
        get product_path(product.slug)
        post cart_items_path, params: {
          authenticity_token: request_csrf_token,
          variant_id: variant.id,
          quantity:
        }
      end

      def start_pickup_checkout(email: "guest@example.com")
        get checkout_path
        post checkout_path, params: {
          authenticity_token: request_csrf_token,
          email:,
          delivery_method: "pickup",
          pickup_location_id: pickup_location.id
        }
      end

      def stub_tax_payment(intent_id:, tax_cents: 500)
        allow(Payments::StripeTaxPayment).to receive(:create) do |order:|
          order.update!(
            stripe_tax_calculation_id: "taxcalc_#{order.id}",
            stripe_payment_intent_id: intent_id,
            tax_amount_cents: tax_cents,
            total_cents: order.subtotal_cents + tax_cents
          )
          double(
            payment_intent: double(
              id: intent_id,
              client_secret: "pi_secret_test",
              status: "requires_payment_method"
            )
          )
        end
      end

      it "adds a selected Variant to a guest Cart and allows quantity updates" do
        add_variant_to_cart
        expect(response).to redirect_to(cart_path)

        get cart_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Cart shirt", "USD 50.00")
        item = CartItem.sole

        patch cart_item_path(item), params: {
          authenticity_token: request_csrf_token,
          cart_item: { quantity: "2" }
        }

        expect(response).to redirect_to(cart_path)
        expect(item.reload.quantity).to eq(2)
      end

      it "allows pickup checkout without completing shipping address fields" do
        add_variant_to_cart
        get checkout_path
        document = Nokogiri::HTML(response.body)

        expect(document.at_css('input[name="shipping_address[line1]"]')["required"]).to be_nil
        expect(document.at_css('select[name="pickup_location_id"]')).to be_present
      end

      it "rejects checkout if a Variant becomes unavailable and leaves the Cart unchanged" do
        add_variant_to_cart
        variant.update!(stock_quantity: 0)
        start_pickup_checkout

        expect(response).to have_http_status(:unprocessable_content)
        expect(CartItem.sole.quantity).to eq(1)
        expect(Cart.sole.status).to eq("open")
        expect(variant.reload.stock_quantity).to eq(0)
        expect(Order.count).to eq(0)
      end

      it "reserves stock, calculates tax at pickup, snapshots prices, and opens the Payment Element" do
        add_variant_to_cart(quantity: 2)
        expect(Payments::StripeTaxPayment).to receive(:create) do |order:|
          expect(order.subtotal_cents).to eq(10_000)
          expect(order.items.sole.unit_amount_cents).to eq(5_000)
          expect(order.shipping_address_line1).to eq("10 Market Street")
          expect(order.delivery_method).to eq("pickup")
          double(payment_intent: double(id: "pi_test_order", client_secret: "pi_secret", status: "requires_payment_method")).tap do
            order.update!(
              stripe_tax_calculation_id: "taxcalc_test",
              stripe_payment_intent_id: "pi_test_order",
              tax_amount_cents: 500,
              total_cents: 10_500
            )
          end
        end

        start_pickup_checkout(email: " Guest@Example.com ")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("pi_secret", "USD 5.00", "USD 105.00", "Main store")
        order = Order.sole
        expect(order.email).to eq("guest@example.com")
        expect(order.status).to eq("pending_payment")
        expect(order.stripe_payment_intent_id).to eq("pi_test_order")
        expect(order.cart.status).to eq("checkout")
        expect(variant.reload.stock_quantity).to eq(2)
      end

      it "marks an Order paid only after a verified Stripe PaymentIntent succeeds" do
        add_variant_to_cart
        stub_tax_payment(intent_id: "pi_test_paid")
        start_pickup_checkout
        order = Order.sole
        payment_intent = double(
          id: "pi_test_paid",
          metadata: double(order_id: order.id.to_s),
          status: "succeeded",
          currency: "usd",
          amount_received: order.total_cents
        )
        event = double(type: "payment_intent.succeeded", data: double(object: payment_intent))
        allow(Stripe::Webhook).to receive(:construct_event).and_return(event)

        post stripe_webhook_path, params: "{}", headers: { "Stripe-Signature" => "verified" }

        expect(response).to have_http_status(:ok)
        expect(order.reload.status).to eq("paid")
        expect(order.cart.reload.status).to eq("completed")
        get order_path(order.public_token)
        expect(response.body).to include("Your Order is confirmed.", "Cart shirt")
      end

      it "keeps the reservation after a failed payment attempt so the guest can retry" do
        add_variant_to_cart(quantity: 2)
        stub_tax_payment(intent_id: "pi_test_failed")
        start_pickup_checkout
        order = Order.sole
        payment_intent = double(
          id: "pi_test_failed",
          metadata: double(order_id: order.id.to_s),
          status: "requires_payment_method"
        )
        event = double(
          type: "payment_intent.payment_failed",
          data: double(object: payment_intent)
        )
        allow(Stripe::Webhook).to receive(:construct_event).and_return(event)

        post stripe_webhook_path, params: "{}", headers: { "Stripe-Signature" => "verified" }

        expect(response).to have_http_status(:ok)
        expect(order.reload.status).to eq("pending_payment")
        expect(order.cart.reload.status).to eq("checkout")
        expect(variant.reload.stock_quantity).to eq(2)
        expect(CartItem.sole.quantity).to eq(2)

        successful_retry = double(
          id: "pi_test_failed",
          metadata: double(order_id: order.id.to_s),
          status: "succeeded",
          currency: "usd",
          amount_received: order.total_cents
        )
        allow(Stripe::Webhook).to receive(:construct_event).and_return(
          double(type: "payment_intent.succeeded", data: double(object: successful_retry))
        )
        post stripe_webhook_path, params: "{}", headers: { "Stripe-Signature" => "verified" }

        expect(response).to have_http_status(:ok)
        expect(order.reload.status).to eq("paid")
        expect(variant.reload.stock_quantity).to eq(2)
      end

      it "restores reserved stock after a PaymentIntent is canceled" do
        add_variant_to_cart(quantity: 2)
        stub_tax_payment(intent_id: "pi_test_canceled")
        start_pickup_checkout
        order = Order.sole
        payment_intent = double(
          id: "pi_test_canceled",
          metadata: double(order_id: order.id.to_s),
          status: "canceled"
        )
        allow(Stripe::Webhook).to receive(:construct_event).and_return(
          double(type: "payment_intent.canceled", data: double(object: payment_intent))
        )

        post stripe_webhook_path, params: "{}", headers: { "Stripe-Signature" => "verified" }

        expect(response).to have_http_status(:ok)
        expect(order.reload.status).to eq("payment_failed")
        expect(order.cart.reload.status).to eq("open")
        expect(variant.reload.stock_quantity).to eq(4)
      end

      it "cancels and releases abandoned PaymentIntents after the reservation expires" do
        add_variant_to_cart
        stub_tax_payment(intent_id: "pi_test_abandoned")
        start_pickup_checkout
        order = Order.sole
        order.update!(payment_expires_at: 1.second.ago)
        allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(
          double(id: "pi_test_abandoned", status: "requires_payment_method")
        )
        expect(Stripe::PaymentIntent).to receive(:cancel) do |intent_id, params, options|
          expect(intent_id).to eq("pi_test_abandoned")
          expect(params).to eq({})
          expect(options).to eq(api_key: "sk_test_fake")
        end

        OrderExpirationJob.perform_now(order.id)

        expect(order.reload.status).to eq("expired")
        expect(order.cart.reload.status).to eq("open")
        expect(variant.reload.stock_quantity).to eq(4)
        expect(CartItem.sole.quantity).to eq(1)
      end

      it "restores inventory and reopens the Cart when Stripe is not configured" do
        add_variant_to_cart
        allow(Payments::StripeTaxPayment).to receive(:create).and_raise(
          Payments::StripeTaxPayment::ConfigurationError, "STRIPE_SECRET_KEY is not configured"
        )

        start_pickup_checkout

        expect(response).to have_http_status(:bad_gateway)
        expect(Order.sole.status).to eq("payment_failed")
        expect(Cart.sole.status).to eq("open")
        expect(variant.reload.stock_quantity).to eq(4)
      end

      it "allows an idempotent retry when Stripe payment setup times out" do
        add_variant_to_cart
        calls = 0
        allow(Payments::StripeTaxPayment).to receive(:create) do
          calls += 1
          raise Stripe::APIConnectionError.new("connection timed out") if calls == 1
          double(payment_intent: double(client_secret: "pi_secret_test", status: "requires_payment_method"))
        end
        start_pickup_checkout

        expect(response).to have_http_status(:bad_gateway)
        order = Order.sole
        expect(order.status).to eq("pending_payment")
        expect(variant.reload.stock_quantity).to eq(3)

        allow(Payments::StripeTaxPayment).to receive(:create).and_return(
          double(payment_intent: double(client_secret: "pi_secret_test", status: "requires_payment_method"))
        )
        get checkout_path
        post checkout_path, params: { authenticity_token: request_csrf_token, email: "guest@example.com" }

        expect(response).to have_http_status(:ok)
        expect(Order.count).to eq(1)
        expect(variant.reload.stock_quantity).to eq(3)
      end

      it "does not confirm payment when a signed Stripe event amount does not match" do
        add_variant_to_cart
        stub_tax_payment(intent_id: "pi_test_mismatch")
        start_pickup_checkout
        order = Order.sole
        payment_intent = double(
          id: "pi_test_mismatch",
          metadata: double(order_id: order.id.to_s),
          status: "succeeded",
          currency: "usd",
          amount_received: order.total_cents + 1
        )
        allow(Stripe::Webhook).to receive(:construct_event).and_return(
          double(type: "payment_intent.succeeded", data: double(object: payment_intent))
        )

        post stripe_webhook_path, params: "{}", headers: { "Stripe-Signature" => "verified" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(order.reload.status).to eq("pending_payment")
      end

      it "rejects an invalid Stripe signature" do
        allow(Stripe::Webhook).to receive(:construct_event).and_raise(Stripe::SignatureVerificationError.new("invalid", "signature"))

        post stripe_webhook_path, params: "{}", headers: { "Stripe-Signature" => "invalid" }

        expect(response).to have_http_status(:bad_request)
      end
    end

    it "shows published Products with the configured market Currency and Variant availability" do
      product = Product.create!(slug: "linen-shirt", status: "published", material: "Linen")
      product.translations.create!(locale: "en", name: "Linen shirt", description: "A breathable shirt")
      product.translations.create!(locale: "en-GB", name: "Linen shirt GB", description: "A breathable shirt")
      variant = product.variants.create!(sku: "LINEN-S", size: "S", color: "Blue", stock_quantity: 2)
      variant.prices.create!(currency: "USD", amount_cents: 7_900)
      variant.prices.create!(currency: "GBP", amount_cents: 6_500)
      Product.create!(slug: "draft-shirt", status: "draft").translations.create!(locale: "en", name: "Draft shirt")

      get products_path(market: "GB")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Linen shirt GB", "GBP 65.00", "Prices in GBP")
      expect(response.body).not_to include("USD 79.00", "Draft shirt")

      get product_path(product.slug, market: "GB")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Material: Linen", "Available", "GBP 65.00")
    end

    it "filters Products by search and Variant attributes" do
      collection = Collection.create!(slug: "summer", status: "published")
      collection.translations.create!(locale: "en", name: "Summer")
      product = Product.create!(slug: "summer-dress", status: "published")
      product.translations.create!(locale: "en", name: "Summer dress", description: "Cotton")
      product.collections << collection
      variant = product.variants.create!(sku: "DRESS-M", size: "M", color: "Red", fit: "Regular", stock_quantity: 1)
      variant.prices.create!(currency: "USD", amount_cents: 12_000)
      other = Product.create!(slug: "winter-coat", status: "published")
      other.translations.create!(locale: "en", name: "Winter coat")

      get products_path(market: "US", q: "summer", collection: "summer", size: "M", color: "Red", fit: "Regular", available: "true")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Summer dress")
      expect(response.body).not_to include("Winter coat")

      get products_path(market: "US", max_price_cents: "13000", sort: "price_asc")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Summer dress")
      expect(response.body).not_to include("Winter coat")

      get collection_path(collection.slug, market: "US")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Summer", "Summer dress")
    end

    it "rejects unsupported markets and malformed price filters" do
      get products_path(market: "ZZ")
      expect(response).to have_http_status(:bad_request)

      get products_path(market: "US", min_price_cents: "not-a-number")
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "admin authentication" do
    let!(:admin_user) do
      AdminUser.create!(email: "staff@example.com", password: "secure-password-123")
    end

    before do
      Rails.cache.clear
    end

    it "requires authentication for the admin dashboard" do
      get admin_root_path

      expect(response).to redirect_to(new_admin_session_path)
    end

    it "authenticates an admin user and provides access to the dashboard" do
      post_admin_session(email: "  STAFF@EXAMPLE.COM ", password: "secure-password-123")

      expect(response).to redirect_to(admin_root_path)

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Commerce admin")
    end

    it "rejects an incorrect password" do
      post_admin_session(email: admin_user.email, password: "wrong-password")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Email or password is incorrect.")
    end

    it "returns the Admin to the protected page requested before sign-in" do
      get admin_root_path(tab: "orders")

      post_admin_session(email: admin_user.email, password: "secure-password-123")

      expect(response).to redirect_to(admin_root_path(tab: "orders"))
    end

    it "preserves the first protected page requested before sign-in" do
      get admin_root_path(tab: "orders")
      get admin_root_path(tab: "returns")

      post_admin_session(email: admin_user.email, password: "secure-password-123")

      expect(response).to redirect_to(admin_root_path(tab: "orders"))
    end

    it "does not redirect to a caller-supplied external destination" do
      post_admin_session(
        email: admin_user.email,
        password: "secure-password-123",
        return_to: "https://example.com"
      )

      expect(response).to redirect_to(admin_root_path)
    end

    it "rotates the session when authentication succeeds" do
      get admin_root_path
      session_cookie = cookies[Rails.application.config.session_options[:key]]

      post_admin_session(email: admin_user.email, password: "secure-password-123")

      expect(cookies[Rails.application.config.session_options[:key]]).not_to eq(session_cookie)
    end

    it "clears an Admin session when the Admin account no longer exists" do
      post_admin_session(email: admin_user.email, password: "secure-password-123")
      admin_user.destroy!

      get admin_root_path

      expect(response).to redirect_to(new_admin_session_path)
    end

    it "invalidates access after sign-out" do
      post_admin_session(email: admin_user.email, password: "secure-password-123")
      get admin_root_path
      token = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')&.[]("value")
      delete admin_session_path, params: { authenticity_token: token }
      get admin_root_path

      expect(response).to redirect_to(new_admin_session_path)
    end

    it "uses the same response for an unknown email and incorrect password" do
      post_admin_session(email: "unknown@example.com", password: "wrong-password")
      unknown_email_response = normalized_auth_error_response

      post_admin_session(email: admin_user.email, password: "wrong-password")

      expect(normalized_auth_error_response).to eq(unknown_email_response)
    end

    it "throttles repeated failed attempts without identifying the account" do
      limit = Rails.application.config.x.commerce.admin_authentication.fetch(:failed_attempt_limit)
      limit.times do
        post_admin_session(email: admin_user.email, password: "wrong-password")
        expect(response).to have_http_status(:unprocessable_content)
      end

      post_admin_session(email: admin_user.email, password: "secure-password-123")

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include("Too many sign-in attempts. Try again later.")
    end

    it "rejects passwords shorter than the configured minimum" do
      short_password_admin = AdminUser.new(email: "short@example.com", password: "short")

      expect(short_password_admin).not_to be_valid
      expect(short_password_admin.errors[:password]).to be_present
    end

    it "normalizes email addresses before enforcing uniqueness" do
      duplicate_admin = AdminUser.new(email: " STAFF@example.com ", password: "another-secure-password")

      expect(duplicate_admin).not_to be_valid
      expect(duplicate_admin.errors[:email]).to be_present
    end

    it "stores only a password digest" do
      expect(admin_user.password_digest).not_to eq("secure-password-123")
      expect(admin_user.authenticate("secure-password-123")).to eq(admin_user)
    end

    it "rejects sign-in without a valid CSRF token" do
      get new_admin_session_path
      post admin_session_path, params: { email: admin_user.email, password: "secure-password-123" }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "Admin catalog management" do
    let!(:admin_user) do
      AdminUser.create!(email: "catalog-staff@example.com", password: "secure-password-123")
    end

    it "requires authentication to manage Products" do
      get admin_products_path

      expect(response).to redirect_to(new_admin_session_path)
    end

    it "creates a Product with localized content, a priced Variant, and Collection membership" do
      collection = Collection.create!(slug: "summer", status: "draft")
      post_admin_session(email: admin_user.email, password: "secure-password-123")
      get new_admin_product_path
      token = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')&.[]("value")

      post admin_products_path, params: {
        authenticity_token: token,
        product: {
          slug: "summer-shirt",
          status: "published",
          material: "Cotton",
          collection_ids: [ "", collection.id ],
          translations_attributes: { "0" => { locale: "en", name: "Summer shirt", description: "A cotton shirt" } },
          variants_attributes: {
            "0" => {
              sku: "SUMMER-S",
              size: "S",
              color: "White",
              fit: "Regular",
              stock_quantity: "3",
              prices_attributes: {
                "0" => { currency: "USD", amount_cents: "4900" },
                "1" => { currency: "GBP", amount_cents: "3900" }
              }
            }
          }
        }
      }

      expect(response).to redirect_to(admin_products_path)
      product = Product.find_by!(slug: "summer-shirt")
      expect(product.translation_for("en").name).to eq("Summer shirt")
      expect(product.collections).to contain_exactly(collection)
      expect(product.variants.first.price_for("USD").amount_cents).to eq(4_900)
      expect(product.variants.first.price_for("GBP").amount_cents).to eq(3_900)

      get new_admin_product_variant_path(product)
      token = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')&.[]("value")
      post admin_product_variants_path(product), params: {
        authenticity_token: token,
        variant: {
          sku: "SUMMER-M",
          size: "M",
          color: "White",
          fit: "Regular",
          stock_quantity: "2",
          prices_attributes: {
            "0" => { currency: "USD", amount_cents: "5100" },
            "1" => { currency: "GBP", amount_cents: "4100" }
          }
        }
      }

      expect(response).to redirect_to(edit_admin_product_path(product))
      expect(product.variants.find_by!(sku: "SUMMER-M").stock_quantity).to eq(2)
    end

    it "supports an ordered Product image gallery with editable alt text and removal" do
      product = Product.create!(slug: "gallery-shirt", status: "published")
      product.translations.create!(locale: "en", name: "Gallery shirt")
      post_admin_session(email: admin_user.email, password: "secure-password-123")

      [ "Front view", "Back view" ].each do |alt_text|
        get edit_admin_product_path(product)
        post admin_product_images_path(product), params: {
          authenticity_token: request_csrf_token,
          product_image: {
            image: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png"),
            alt_text:
          }
        }
        expect(response).to redirect_to(edit_admin_product_path(product))
      end

      first_image, second_image = product.product_images.order(:position).to_a
      expect([ first_image.position, second_image.position ]).to eq([ 1, 2 ])

      get edit_admin_product_path(product)
      patch move_up_admin_product_image_path(product, second_image), params: {
        authenticity_token: request_csrf_token
      }
      expect(product.product_images.order(:position).pluck(:alt_text)).to eq([ "Back view", "Front view" ])

      get edit_admin_product_path(product)
      patch admin_product_image_path(product, second_image), params: {
        authenticity_token: request_csrf_token,
        product_image: { alt_text: "Front view, revised" }
      }
      expect(second_image.reload.alt_text).to eq("Front view, revised")

      get edit_admin_product_path(product)
      delete admin_product_image_path(product, first_image), params: {
        authenticity_token: request_csrf_token
      }
      expect(product.product_images.order(:position).pluck(:position, :alt_text)).to eq([ [ 1, "Front view, revised" ] ])

      get product_path(product.slug)
      expect(response.body).to include('alt="Front view, revised"')
    end

    it "rejects unsupported Product images and enforces the gallery limit" do
      product = Product.create!(slug: "limited-gallery", status: "draft")
      post_admin_session(email: admin_user.email, password: "secure-password-123")

      get edit_admin_product_path(product)
      post admin_product_images_path(product), params: {
        authenticity_token: request_csrf_token,
        product_image: {
          image: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.svg"), "image/svg+xml"),
          alt_text: "Unsupported vector"
        }
      }
      expect(product.product_images).to be_empty

      ProductImage::MAX_IMAGES_PER_PRODUCT.times do |index|
        get edit_admin_product_path(product)
        post admin_product_images_path(product), params: {
          authenticity_token: request_csrf_token,
          product_image: {
            image: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png"),
            alt_text: "Image #{index + 1}"
          }
        }
      end
      expect(product.product_images.count).to eq(ProductImage::MAX_IMAGES_PER_PRODUCT)

      get edit_admin_product_path(product)
      post admin_product_images_path(product), params: {
        authenticity_token: request_csrf_token,
        product_image: {
          image: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png"),
          alt_text: "One too many"
        }
      }
      expect(product.product_images.count).to eq(ProductImage::MAX_IMAGES_PER_PRODUCT)
      expect(flash[:alert]).to include("at most 8 images")
    end

    it "uses one Admin-selected published Collection to drive the homepage feature" do
      first_collection = Collection.create!(slug: "first-edit", status: "published")
      first_collection.translations.create!(locale: "en", name: "First edit")
      featured_collection = Collection.create!(slug: "evening-edit", status: "published")
      featured_collection.translations.create!(locale: "en", name: "Evening edit")
      post_admin_session(email: admin_user.email, password: "secure-password-123")

      get edit_admin_collection_path(first_collection)
      patch admin_collection_path(first_collection), params: {
        authenticity_token: request_csrf_token,
        collection: { featured_on_home: "1" }
      }
      expect(first_collection.reload).to be_featured_on_home

      get edit_admin_collection_path(featured_collection)
      patch admin_collection_path(featured_collection), params: {
        authenticity_token: request_csrf_token,
        collection: { featured_on_home: "1" }
      }
      expect(featured_collection.reload).to be_featured_on_home
      expect(first_collection.reload).not_to be_featured_on_home

      get root_path
      expect(response.body).to include("The current edit · Evening edit", "Explore the edit")
      expect(response.body).to include(collection_path(featured_collection.slug, market: "US"))
    end
  end

  it "loads the configured locale and currencies" do
    configuration = Rails.application.config.x.commerce

    expect(configuration.default_locale).to eq("en")
    expect(configuration.default_currency).to eq("USD")
    expect(configuration.markets).to include(
      US: hash_including(locale: "en", currency: "USD", tax_behavior: "exclusive"),
      GB: hash_including(locale: "en-GB", currency: "GBP", tax_behavior: "inclusive")
    )
    expect(configuration.supported_locales).to contain_exactly("en", "en-GB")
    expect(configuration.supported_currencies).to contain_exactly("USD", "GBP")
    expect(I18n.available_locales).to contain_exactly(:en, :"en-GB")
  end
end
