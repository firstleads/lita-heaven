require "octokit"
require "lita/deploy_request"

module Lita
  module Handlers
    class Heaven < Handler
      namespace :heaven
      config :access_token, type: String, required: true
      config :apps, type: Hash, required: true

      route(/^deploy!?\s+/, :deploy, command: true, help: {
        'deploy app' => 'Deploy app.',
        'deploy app/ref' => 'Deploy app at specific ref (branch / sha / etc)',
        'deploy app to env' => 'Deploy app to environment',
        'deploy app/ref to env' => 'Deploy app at ref to environment',
        'deploy! app to env' => "Force deploy app, ignoring CI and any locks"
      })

      route(/^(un)?lock\s+/, :lock_or_unlock, command: true, help: {
        'lock app in env' => 'Lock app in environent.',
        'unlock app in env' => 'Unlock app in environent.',
      })

      route(/^where can I deploy\s+/i, :where_can_i_deploy, command: true, help: {
        'where can i deploy <app>' => "display latest deployment status for <app>"
      })

      route(/^wcid\s+/, :where_can_i_deploy, command: true, help: {
        'where can i deploy <app>' => "display latest deployment status for <app>"
      })

      def deploy(response)
        target, _, env = response.args
        app, ref = target.split("/")
        app_config = config.apps[app]

        if app_config
          request = DeployRequest.new(message: response.message.body, config: app_config, user: response.user, room: response.room)
          create_deployment(response, request)
          response.reply(request.reply)
        else
          response.reply("#{app} not found")
        end
      end

      def lock_or_unlock(response)
        app = response.args.first
        app_config = config.apps[app]
        if app_config
          request = DeployRequest.new(message: response.message.body, config: app_config, user: response.user, room: response.room)
          create_deployment(response, request)
          response.reply(request.reply)
        else
          response.reply("#{app} not found")
        end
      end

      def where_can_i_deploy(response)
        app = response.args.first
        app_config = config.apps[app]
        msg = ""
        if app_config
          repo = app_config[:repo]
          %w[staging qa production].each do |env|
            deployments = find_deployments(repo, env)
            deployments.each do |deployment|
              deployment_statuses = deployment.rels[:statuses].get.data
              Lita.logger.info("deployment=#{deployment.inspect}")
              Lita.logger.info("deployment_statuses=#{deployment_statuses}")
              most_recent = deployment_statuses.first

              msg << "*#{env}*: #{deployment.payload.actor} deployed #{deployment.ref} at #{deployment.created_at}; state #{most_recent.state}\n"
            end
          end
        else
          msg = "#{app} not found"
        end
        response.reply(msg)
      end

      private

      def find_deployments(repo, environment)
        options = {
          environment: environment,
          per_page: 1
        }
        client = Octokit::Client.new(access_token: config.access_token)
        client.deployments(repo, options)
      end

      # https://developer.github.com/v3/repos/deployments/#create-a-deployment
      def create_deployment(response, request)
        Lita.logger.info("event=create_deployment repo=#{request.repo} ref=#{request.ref} env=#{request.env} task=#{request.task} payload=#{request.payload}")
        client = Octokit::Client.new(access_token: config.access_token)
        begin
          options = {
            environment: request.env,
            payload: request.payload,
            task: request.task,
            auto_merge: request.auto_merge,
          }
          options.merge!(required_contexts: []) if request.forced?
          client.create_deployment(request.repo, request.ref, options)
        rescue Octokit::Error => e
          response.reply("#{e.response_status} error creating deployment")
          response.reply(e.message)
          raise e
        end
      end

      Lita.register_handler(self)
    end
  end
end
