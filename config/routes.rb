Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  devise_for :users

  # Defines the root path route ("/")
  root to: "application#index"

  get "students/dashboard", as: :students_root
  get "admin/dashboard", as: :admin_root
  patch "user_settings", to: "user_settings#update"

  namespace :admin do
    resources :courses do
      post "generate_outline", on: :member
      resources :lessons do
        get "printable", on: :collection
        post "generate_lessons", on: :collection
        patch "move_higher", on: :member
        patch "move_lower", on: :member
        resource :lesson_plan, only: [ :edit, :update, :destroy ] do
          post "link_resource/:resource_id", to: "lesson_plans#link_resource", as: :link_resource
          delete "unlink_resource/:resource_id", to: "lesson_plans#unlink_resource", as: :unlink_resource
          get "new_resource", to: "lesson_plans#new_resource", as: :new_resource
          post "generate_content", to: "lesson_plans#generate_content", as: :generate_content
        end
      end
    end

    resources :prompts

    resources :resources do
      delete "delete_file", on: :member
    end

    resources :tools, only: [ :index, :show, :edit, :update ]

    resources :completions, only: [ :index ]

    resources :students, only: [ :index, :show ] do
      member do
        post :adopt
        delete :unadopt
        post :enroll
        delete :unenroll
      end
    end
  end

  namespace :student do
    resources :lessons, only: [ :show ]
  end

  resources :applets

  resources :conversations do
    member do
      delete :clear
    end
    resources :messages, only: [ :create ]
  end

  get "proxy/image", to: "messages#proxy_image"
end
