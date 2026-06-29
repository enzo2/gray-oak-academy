namespace :db do
  namespace :seed do
    desc "Refresh seeded default Prompts and Tools, then reload db/seeds.rb"
    task refresh_defaults: :environment do
      DefaultSeedRefreshService.call
    end
  end
end
