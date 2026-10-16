require "rails_helper"

RSpec.describe Payments::StripeTaxPayment do
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
  let!(:cart) do
    Cart.create!(token: SecureRandom.hex(32), market_code: "US", currency: "USD", locale: "en")
  end
  let!(:order) do
    cart.orders.create!(
      public_token: SecureRandom.urlsafe_base64(32),
      market_code: "US",
      email: "guest@example.com",
      currency: "USD",
      locale: "en",
      delivery_method: "pickup",
      pickup_location: pickup_location,
      shipping_address_line1: pickup_location.address_line1,
      shipping_city: pickup_location.city,
      shipping_state: pickup_location.state,
      shipping_postal_code: pickup_location.postal_code,
      shipping_country_code: pickup_location.country_code,
      subtotal_cents: 5_000,
      total_cents: 5_000,
      payment_expires_at: 35.minutes.from_now
    )
  end
  let!(:variant) do
    product = Product.create!(slug: "stripe-shirt", status: "published")
    product.variants.create!(sku: "STRIPE-S", size: "S", stock_quantity: 1)
  end

  before do
    order.items.create!(
      variant:,
      sku: variant.sku,
      product_name: "Saved shirt name",
      variant_description: "Black / S",
      quantity: 1,
      unit_amount_cents: 5_000,
      line_total_cents: 5_000
    )
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("STRIPE_SECRET_KEY").and_return("sk_test_fake")
    allow(ENV).to receive(:[]).with("STRIPE_PUBLISHABLE_KEY").and_return("pk_test_fake")
  end

  it "creates a Tax Calculation and PaymentIntent using the pickup destination and saved Order" do
    calculation = double(
      id: "taxcalc_test",
      amount_total: 5_575,
      shipping_cost: nil,
      tax_amount_exclusive: 575,
      tax_amount_inclusive: 0
    )
    expect(Stripe::Tax::Calculation).to receive(:create).with(
      hash_including(
        currency: "usd",
        customer_details: {
          address: {
            line1: "10 Market Street",
            city: "San Francisco",
            state: "CA",
            postal_code: "94105",
            country: "US"
          },
          address_source: "shipping"
        },
        line_items: [
          {
            amount: 5_000,
            quantity: 1,
            reference: "order_item_#{order.items.sole.id}",
            tax_behavior: "exclusive"
          }
        ]
      ),
      { api_key: "sk_test_fake", idempotency_key: "onthelist-tax-#{order.id}" }
    ).and_return(calculation)
    expect(Stripe::PaymentIntent).to receive(:create).with(
      hash_including(
        amount: 5_575,
        currency: "usd",
        receipt_email: "guest@example.com",
        metadata: { order_id: order.id.to_s },
        hooks: { inputs: { tax: { calculation: "taxcalc_test" } } }
      ),
      { api_key: "sk_test_fake", idempotency_key: "onthelist-payment-taxcalc_test" }
    ).and_return(double(id: "pi_test", client_secret: "pi_secret_test", status: "requires_payment_method"))

    result = described_class.create(order:)

    expect(result.calculation).to eq(calculation)
    expect(result.payment_intent.id).to eq("pi_test")
    expect(order.reload).to have_attributes(
      stripe_tax_calculation_id: "taxcalc_test",
      stripe_payment_intent_id: "pi_test",
      subtotal_cents: 5_000,
      tax_amount_cents: 575,
      shipping_amount_cents: 0,
      total_cents: 5_575
    )
  end

  it "reuses the saved Tax Calculation and PaymentIntent on retry" do
    order.update!(stripe_tax_calculation_id: "taxcalc_saved", stripe_payment_intent_id: "pi_saved")
    calculation = double(
      id: "taxcalc_saved",
      amount_total: 5_250,
      shipping_cost: nil,
      tax_amount_exclusive: 250,
      tax_amount_inclusive: 0
    )
    expect(Stripe::Tax::Calculation).to receive(:retrieve).with("taxcalc_saved", { api_key: "sk_test_fake" })
      .and_return(calculation)
    expect(Stripe::PaymentIntent).to receive(:retrieve).with("pi_saved", { api_key: "sk_test_fake" })
      .and_return(double(id: "pi_saved", client_secret: "pi_secret_saved", status: "requires_payment_method"))
    expect(Stripe::Tax::Calculation).not_to receive(:create)
    expect(Stripe::PaymentIntent).not_to receive(:create)

    expect(described_class.create(order:).payment_intent.id).to eq("pi_saved")
  end

  it "includes the configured market shipping rate in Stripe Tax for shipping Orders" do
    order.update!(delivery_method: "shipping", pickup_location: nil)
    market = Rails.application.config.x.commerce.markets.fetch(:US)
    allow(market).to receive(:[]).and_call_original
    allow(market).to receive(:[]).with(:stripe_shipping_rate_id).and_return("shr_test_flat_rate")
    calculation = double(
      id: "taxcalc_shipping",
      amount_total: 5_900,
      shipping_cost: double(amount: 500),
      tax_amount_exclusive: 400,
      tax_amount_inclusive: 0
    )
    allow(Stripe::PaymentIntent).to receive(:create).and_return(
      double(id: "pi_shipping", client_secret: "pi_secret_shipping", status: "requires_payment_method")
    )

    expect(Stripe::Tax::Calculation).to receive(:create).with(
      hash_including(shipping_cost: { shipping_rate: "shr_test_flat_rate" }),
      { api_key: "sk_test_fake", idempotency_key: "onthelist-tax-#{order.id}" }
    ).and_return(calculation)

    described_class.create(order:)

    expect(order.reload).to have_attributes(shipping_amount_cents: 500, tax_amount_cents: 400, total_cents: 5_900)
  end

  it "fails explicitly when Stripe credentials are missing" do
    allow(ENV).to receive(:[]).with("STRIPE_SECRET_KEY").and_return(nil)

    expect { described_class.create(order:) }
      .to raise_error(described_class::ConfigurationError, "STRIPE_SECRET_KEY is not configured")
  end
end
