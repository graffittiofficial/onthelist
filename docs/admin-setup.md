# Admin access

Create the first Admin account from an interactive terminal:

```sh
docker compose up -d --wait redis
bin/rails admin:create
```

The task prompts for an email address and a password of at least 12 characters. Password input is not echoed. The Admin dashboard is available at `/admin`.

The local Redis service is bound to `127.0.0.1:6379` and is ready when its Compose health check passes. Start it independently of the Rails processes with `docker compose up -d --wait redis`; stop and remove it with `docker compose down`. Its cache and job-queue data is disposable and is not persisted.

Manage catalog Products at `/admin/products` and Collections at `/admin/collections`. Product prices are entered in minor currency units (for example, 4900 for USD 49.00) and configured separately for each supported Currency. Product imagery is optional; each saved Product can have up to eight ordered JPEG, PNG, or WebP images (10 MB maximum each) with descriptive alt text. Upload original or properly licensed photography. The first image is used for catalog cards and the homepage feature when the Product belongs to the featured Collection. Only published Products and Collections appear in the Store.

Mark one Collection as the homepage feature from its Admin form. Its first published Product supplies the feature image when it has one; otherwise the Store displays a designed fallback. Do not rely on the local production upload volume as the only backup: arrange off-host backups. The configured single-host volume is not shared across hosts, so use shared object storage before running multiple app hosts.

## Stripe checkout

The Store uses Stripe Payment Element with Stripe Tax and never handles or stores card numbers. Configure `STRIPE_SECRET_KEY` and `STRIPE_PUBLISHABLE_KEY` in the local environment and use Stripe test keys for development. Configure the deployed canonical hostname with `APP_HOST` (without a scheme); production payment return URLs require it. Set `APP_PROTOCOL` only when the deployment does not use HTTPS.

In Stripe, add tax registrations for the jurisdictions the Store serves and set the account's default Product tax code to the appropriate apparel code. Market prices use tax-exclusive behavior in the US and tax-inclusive behavior in GB. Configure a flat Stripe Shipping Rate per shipping market and set its ID as `STRIPE_SHIPPING_RATE_US` or `STRIPE_SHIPPING_RATE_GB`. Checkout calculates shipping and tax for the entered shipping destination; pickup uses the selected pickup location address and adds no shipping fee.

Configure a Stripe webhook endpoint at `/webhooks/stripe` with the `payment_intent.succeeded`, `payment_intent.payment_failed`, and `payment_intent.canceled` events, and provide its signing secret as `STRIPE_WEBHOOK_SECRET`. For local testing, Stripe CLI can forward events to `localhost:3000/webhooks/stripe`; use the signing secret printed by `stripe listen`. An Order is confirmed only by a valid signed event whose amount and Currency match the saved Order. Checkout reserves stock while payment is pending. A failed payment attempt keeps the reservation so the guest can retry; canceled or expired payments restore stock.

Reset an Admin password through the same private interactive workflow:

```sh
bin/rails admin:reset_password
```

The task prompts for the registered email and a confirmed password without echoing password input. Do not pass credentials as command-line arguments.

The initial commerce configuration is in `config/commerce.yml`. It includes sample US/USD and GB/GBP market settings; update these to match the markets the Store actually serves.

Redis provides the development and production cache store and Sidekiq's job queue. Start local Redis before launching the development Procfile, which starts the Sidekiq worker. The development cache defaults to `redis://127.0.0.1:6379/1`; set `REDIS_CACHE_URL` and `REDIS_URL` to use an externally managed development Redis service instead. The Compose service is development-only and does not configure production Redis.

Production requires `REDIS_URL` for Sidekiq and `REDIS_CACHE_URL` for the cache store. Configure both as deployment secrets; they may point to the same Redis service if it is sized and configured for both workloads.

Admin sign-in is throttled after five failed attempts from the same client IP or normalized email address. Counters expire after 15 minutes; a successful sign-in clears the email counter.
