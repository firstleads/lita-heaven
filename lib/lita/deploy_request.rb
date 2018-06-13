module Lita
  class DeployRequest
    attr_reader :config
    attr_reader :ref
    attr_reader :task
    attr_reader :user

    DEFAULT_REF = "master"
    DEFAULT_ENV = "production"
    DEFAULT_AUTOMERGE = true

    class NullUser
      def mention_name
        "unknown"
      end
    end

    VALID_SLUG = "([-_\.0-9a-z]+)"

    def self.pattern_parts
      [
        "(deploy|lock|unlock)",                # / prefix
        "(!)?\s+",                                      # Whether or not it was a forced deployment
        VALID_SLUG,                                     # application name
        "(?:\/([^\s]+))?",                              # ref to deploy
        "(?:\s+(?:to|in|on)\s+",                        # to | in | on
        VALID_SLUG,                                     # Environment to release to
        ")"
      ]
    end

    def initialize(message:, config:, user: NullUser.new, room: nil)
      @message = message
      @config = config
      @user = user
      @room = room

      matches = self.class.text_to_deployment_args(@message)

      @command = matches[:command]
      @app = matches[:app]
      @ref = matches[:ref]
      @env = matches[:environment]
      @forced = matches[:forced]

      @ref ||= config.fetch(:default_ref, DEFAULT_REF)
      @env ||= config.fetch(:default_env, DEFAULT_ENV)
      @auto_merge_on_standard_deploys = config.fetch(:auto_merge_on_standard_deploys, DEFAULT_AUTOMERGE)
    end

    def self.text_to_deployment_args(text)
      deploy_pattern = Regexp.new(pattern_parts.join(""))
      matches = deploy_pattern.match(text)
      return {} unless matches
      {
        command: matches[1],
        forced: matches[2] == "!",
        app: matches[3],
        ref: matches[4] || DEFAULT_REF,
        environment: matches[5],
      }
    end

    def auto_merge
      if forced?
        false
      else
        @auto_merge_on_standard_deploys
      end
    end

    def forced?
      @forced
    end

    def reply
      case
      when ["lock", "unlock"].include?(@command)
        "#{user.mention_name} is #{@command}ing #{repo} in #{env}"
      when @command == "deploy" && forced?
        "#{user.mention_name} is force #{@command}ing #{repo}/#{ref} to #{env}"
      when @command == "deploy"
        "#{user.mention_name} is #{@command}ing #{repo}/#{ref} to #{env}"
      else
        Lita.logger.error("event=unknown_reply message=#{@message}")
      end
    end

    def env
      case @env
      when "stg"
        "staging"
      when "prod", "prd"
        "production"
      else
        @env
      end
    end

    def task
      case @command
      when "lock", "unlock"
        "deploy:#{@command}"
      else
        @command
      end
    end

    def repo
      config.fetch(:repo)
    end

    def payload
      app_payload = config.fetch(:payload, {}).dup
      payload = merge_payload_defaults(app_payload)
    end

    private

    # Merge defaults that Heaven expects for things like chat notifications,
    # so it can show the actual user who is rseponsible for the deploy.
    def merge_payload_defaults(hsh)
      hsh[:actor] = @user.mention_name
      notify_data = {}
      notify_data.merge!(user: @user.mention_name) unless NullUser === @user
      notify_data.merge!(room: @room.name) if @room
      hsh[:notify] = notify_data
      hsh
    end

  end
end
