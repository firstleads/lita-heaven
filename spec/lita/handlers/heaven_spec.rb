require "spec_helper"

RSpec.describe Lita::Handlers::Heaven, lita_handler: true do
  let(:app_config) { { repo: "testuser/myapp" } }
  let(:deployments_url) { "https://api.github.com/repos/testuser/myapp/deployments" }

  it { is_expected.to route_command("deploy myapp").to(:deploy) }
  it { is_expected.to route_command("deploy myapp/branch to staging").to(:deploy) }
  it { is_expected.to route_command("where can i deploy myapp").to(:where_can_i_deploy) }
  it { is_expected.to route_command("where can I deploy myapp").to(:where_can_i_deploy) }
  it { is_expected.to route_command("wcid myapp").to(:where_can_i_deploy) }

  context "wcid" do
    before do
      robot.config.handlers.heaven.access_token = "myaccesstoken"
      robot.config.handlers.heaven.apps = {
        "myapp" => { repo: "testuser/myapp" }
      }
    end

    xit "works" do
      deployments = []
      expect_any_instance_of(Lita::Handlers::Heaven).to receive(:find_deployments).times(3).and_return([])
      send_command "wcid myapp"
    end
  end

  context "locks" do
    before do
      robot.config.handlers.heaven.access_token = "myaccesstoken"
      robot.config.handlers.heaven.apps = {
        "myapp" => { repo: "testuser/myapp" }
      }
    end

    it "sends lock task to heaven" do
      stub = stub_request(:post, deployments_url)
        .with(
          body: hash_including(task: "deploy:lock", ref: "master"),
          headers: {"Authorization" => "token myaccesstoken"})

      send_command "lock myapp in production"
      expect(stub).to have_been_requested
    end

    it "sends unlock task to heaven" do
      stub = stub_request(:post, deployments_url)
        .with(
          body: hash_including(task: "deploy:unlock", ref: "master"),
          headers: {"Authorization" => "token myaccesstoken"})

      send_command "unlock myapp in stg"
      expect(stub).to have_been_requested
    end

    it "tells you about the successful lock" do
      stub = stub_request(:post, deployments_url)
      send_command "lock myapp in production"
      expect(replies.last).to eq("Test User is locking testuser/myapp in production")
    end

    it "tells you about the successful lock" do
      stub = stub_request(:post, deployments_url)
      send_command "unlock myapp in prod"
      expect(replies.last).to eq("Test User is unlocking testuser/myapp in production")
    end

    it "returns not found if app isn't configured" do
      send_command "lock foo"
      expect(replies.last).to eq("foo not found")
    end
  end

  context "deploys"  do
    before do
      robot.config.handlers.heaven.access_token = "myaccesstoken"
      robot.config.handlers.heaven.apps = {
        "myapp" => { repo: "testuser/myapp" }
      }
    end

    it "deploys to default ref and environment" do
      stub = stub_request(:post, deployments_url)
        .with(
          body: hash_including(environment: "production", ref: "master"),
          headers: {"Authorization" => "token myaccesstoken"})

      send_command "deploy myapp"
      expect(stub).to have_been_requested
    end

    it "sets auto_merge to false if configured as false in the app config" do
      robot.config.handlers.heaven.apps = {
        "myapp" => {
          repo: "testuser/myapp",
          auto_merge_on_standard_deploys: false }
      }
      stub = stub_request(:post, deployments_url)
        .with(body: hash_including(auto_merge: false))

      send_command "deploy myapp/feature-branch to staging"
      expect(stub).to have_been_requested.at_least_once
    end

    it "deploys to specific environment" do
      stub = stub_request(:post, deployments_url)
        .with(
          body: hash_including(environment: "staging"),
          headers: {"Authorization" => "token myaccesstoken"})

      send_command "deploy myapp to staging"
      expect(stub).to have_been_requested
    end

    it "deploys to specific environment with provided branch" do
      stub = stub_request(:post, deployments_url)
        .with(
          body: hash_including(environment: "branch-lab", ref: "experiment"),
          headers: {"Authorization" => "token myaccesstoken"})

      send_command "deploy myapp/experiment to branch-lab"
      expect(stub).to have_been_requested.at_least_once
    end

    it "deploys to branches with slashes in the name" do
      stub = stub_request(:post, deployments_url)
        .with(
          body: hash_including(environment: "branch-lab", ref: "janedoe/my-branch"),
          headers: {"Authorization" => "token myaccesstoken"})

      send_command "deploy myapp/janedoe/my-branch to branch-lab"
      expect(stub).to have_been_requested.at_least_once
    end

    it "autolocks if deployed to a non-default ref" do
      pending "disabled for now"
      deploy_stub = stub_request(:post, deployments_url).
        with(body: hash_including(task: "deploy", ref: "experiment"))

      lock_stub = stub_request(:post, deployments_url).
        with(body: hash_including(task: "deploy:lock", ref: "experiment"))

      send_command "deploy myapp/experiment to production"
      expect(deploy_stub).to have_been_requested
      expect(lock_stub).to have_been_requested
    end

    it "replies with a nice deployment message" do
      janedoe = Lita::User.create(123, name: "Jane Doe", mention_name: "janedoe")
      stub = stub_request(:post, deployments_url)

      send_command "deploy myapp/experiment to branch-lab", as: janedoe

      expect(replies.last).to eq("janedoe is deploying testuser/myapp/experiment to branch-lab")
    end

    context "force deploys" do
      it "sets required_contexts to empty array and auto_merge to false" do
        stub = stub_request(:post, deployments_url)
          .with(body: hash_including(required_contexts: [], auto_merge: false))

        send_command "deploy! myapp/janedoe/my-branch to branch-lab"
        expect(stub).to have_been_requested.at_least_once
      end
    end

    context "with custom payload configured for the app" do
      before do
        robot.config.handlers.heaven.access_token = "myaccesstoken"
        robot.config.handlers.heaven.apps = {
          "myapp" => {
            repo: "testuser/myapp",
            payload: { "deploy_script" => "script/deploy" }
          }
        }
      end

      it "sends create deployment request that merges custom payload with default" do
        # This is a bit awkward, because we add our own custom things to the payload
        # hash on top of application configured things.  Not sure of a better
        # way to test just the piece we care about here.
        expected_payload_hash = {
          deploy_script: "script/deploy",
          actor: "Test User",
          notify: { "user": "Test User" }
        }
        stub = stub_request(:post, deployments_url)
          .with(body: hash_including(payload: expected_payload_hash))

        send_command("deploy myapp")

        expect(stub).to have_been_requested
      end
    end

    context "when app is not found" do
      before do
        robot.config.handlers.heaven.access_token = "myaccesstoken"
        robot.config.handlers.heaven.apps = {}
      end

      it "returns not found message" do
        send_command("deploy foobar")
        expect(replies.last).to eq("foobar not found")
      end
    end
  end
end
