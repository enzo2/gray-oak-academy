Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "application#manifest", as: :pwa_manifest
  # get "service-worker.js" => "application#service_worker", as: :pwa_service_worker

  devise_for :users, controllers: {
    registrations: "users/registrations"
  }

  # Defines the root path route ("/")
  root to: "application#index"

  patch "user_settings", to: "user_settings#update"
  get "user_settings/llm_models", to: "user_settings#llm_models"

  resources :conversations, only: [ :index, :show, :create, :update, :destroy ] do
    member do
      delete :clear
    end
    resources :messages, only: [ :create ]
    post "audio_messages", to: "messages#create_audio_message"
    post "transcribed_messages", to: "messages#create_transcribed_message"
  end

  get "proxy/image", to: "messages#proxy_image"
  get "messages/:id/tts_stream", to: "messages#tts_stream"

  resources :enrollments, only: [ :show ]

  resources :memories, only: [ :create, :edit, :update, :destroy ]

  resources :applets do
    member do
      post :save_as_resource
    end
  end

  namespace :admin do
    get "dashboard", as: :root, to: "dashboard#dashboard"

    resources :courses do
      post "generate_outline", on: :member
      patch "archive", on: :member
      patch "unarchive", on: :member
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
          delete "remove_suggested_resource/:resource_index", to: "lesson_plans#remove_suggested_resource", as: :remove_suggested_resource
        end
      end
    end

    resources :prompts

    resources :resources do
      delete "delete_file", on: :member
    end

    resources :tools, only: [ :index, :show, :edit, :update ]

    resources :completions, only: [ :index ]

    resources :students, only: [ :index, :show, :destroy ] do
      member do
        get :journal
        post :adopt
        delete :unadopt
        post :enroll
        delete :unenroll
      end
      collection do
        post :new, action: :new_student, as: :new
      end

      resources :memories, only: [ :create, :edit, :update, :destroy ] do
        member do
          patch :toggle_hidden
        end
      end
    end

    resources :supported_apis, only: [ :index, :new, :create, :edit, :update, :destroy ] do
      member do
        post :verify_models
        # delete "models/:model_name", to: "supported_apis#remove_model", as: :remove_model
      end
    end

    # App-wide settings (singleton)
    resource :app_setting, only: [ :edit, :update ]

    resources :llms, only: [ :index, :update ]
    resources :observations, only: [ :create, :show, :edit, :update, :destroy ]
  end

  namespace :student do
    get "dashboard", as: :root, to: "dashboard#dashboard"
    get "journal", to: "dashboard#journal"
    resources :lessons, only: [ :show ]
    resources :observations, only: [ :update ]
    resources :student_feedbacks, only: [ :create ]
  end
end
