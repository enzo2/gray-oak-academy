- The dev server uses https. When using any browser tool to view the site locally, use https://localhost:3000. Login with lucas@policastromd.com / admin1

- All tests require Postgres DB access, so if you have a "sandbox_permissions: require_escalated" option, this is needed for running tests. e.g. DB_HOST=postgres bundle exec rails test <paths>