Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "storefront/home#index"
  get "products", to: "storefront/products#index", as: :products
  get "products/:slug", to: "storefront/products#show", as: :product
  get "collections/:slug", to: "storefront/collections#show", as: :collection
  resource :cart, only: :show, controller: "storefront/carts" do
    resources :items, only: %i[create update destroy], controller: "storefront/cart_items"
  end
  resource :checkout, only: %i[show create], controller: "storefront/checkouts"
  get "orders/:token", to: "storefront/orders#show", as: :order
  post "webhooks/stripe", to: "webhooks/stripe#create", as: :stripe_webhook

  namespace :admin do
    resource :session, only: %i[new create destroy], controller: "sessions"
    resources :products, only: %i[index new create edit update] do
      resources :variants, only: %i[new create edit update]
      resources :images, only: %i[create update destroy], controller: "product_images" do
        member do
          patch :move_up
          patch :move_down
        end
      end
    end
    resources :collections, only: %i[index new create edit update]
    resources :pickup_locations, only: %i[index new create edit update]
    root "dashboard#show"
  end
end
