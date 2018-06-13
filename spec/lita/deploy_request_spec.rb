require "spec_helper"

RSpec.describe Lita::DeployRequest do
  it "defaults to master on production" do
    req = described_class.new(message: "deploy app", config: {})
    expect(req.ref).to eq("master")
    expect(req.env).to eq("production")
  end

  it "can parse the environment" do
    req = described_class.new(message: "deploy app to staging", config: {})
    expect(req.env).to eq("staging")
  end

  context "forced?" do
    it "is true for bang deploys" do
      req = described_class.new(message: "deploy! app to stg", config: {})
      expect(req.forced?).to be_truthy
    end

    it "is false for everything else" do
      req = described_class.new(message: "deploy app to stg", config: {})
      expect(req.forced?).to be_falsey
      req = described_class.new(message: "lock app in stg", config: {})
      expect(req.forced?).to be_falsey
    end
  end

  context "auto_merge" do
    it "is true by default for standard deploys" do
      req = described_class.new(message: "deploy app to stg", config: {})
      expect(req.auto_merge).to be_truthy
    end

    it "can be configured to be false for standard deploys" do
      req = described_class.new(message: "deploy app to stg", config: { auto_merge_on_standard_deploys: false })
      expect(req.auto_merge).to be_falsey
    end

    it "is false for force deploys" do
      req = described_class.new(message: "deploy! app to stg", config: {})
      expect(req.auto_merge).to be_falsey
    end
  end

  context "task" do
    it "is deploy for deploy" do
      req = described_class.new(message: "deploy app to staging", config: {})
      expect(req.task).to eq("deploy")
    end

    it "uses deploy for deploy!" do
      req = described_class.new(message: "deploy! app to stg", config: {})
      expect(req.task).to eq("deploy")
    end

    it "is deploy:lock for lock command" do
      req = described_class.new(message: "lock app in stg", config: {})
      expect(req.task).to eq("deploy:lock")
    end
  end

  context "ref" do
    it "can parse the ref" do
      req = described_class.new(message: "deploy app/my-branch to staging", config: {})
      expect(req.ref).to eq("my-branch")
    end

    it "can parse ref with slashes" do
      req = described_class.new(message: "deploy app/my-complicated/branch-name to staging", config: {})
      expect(req.ref).to eq("my-complicated/branch-name")
    end
  end

  context "payload" do
    it "includes the actor in the payload" do
      janedoe = Lita::User.create(123, name: "Jane Doe", mention_name: "janedoe")
      payload = {
        actor: "janedoe",
        notify: { user: "janedoe" }
      }
      req = described_class.new(message: "deploy app/experiment to branch-lab", config: {}, user: janedoe)

      expect(req.payload).to include(payload)
    end

    it "includes the room the message was sent from in the notification payload" do
      devops_room = Lita::Room.new(123, name: "devops")
      payload = { notify: { room: "devops" } }

      req = described_class.new(message: "deploy myapp/experiment to branch-lab", config: {}, room: devops_room)
      expect(req.payload).to include(payload)
    end
  end

  context "reply" do
    let(:config) { { repo: "testuser/myapp" } }

    it "handles unknown user" do
      req = described_class.new(message: "deploy app/mybranch to lab", config: config)
      expect(req.reply).to eq("unknown is deploying testuser/myapp/mybranch to lab")
    end

    it "handles known users" do
      stub_user = instance_double("Lita:User", mention_name: "jamesbond")
      req = described_class.new(message: "deploy app/mybranch to lab", config: config, user: stub_user)
      expect(req.reply).to eq("jamesbond is deploying testuser/myapp/mybranch to lab")
    end

    it "handles force deploys" do
      stub_user = instance_double("Lita:User", mention_name: "jamesbond")
      req = described_class.new(message: "deploy! app/mybranch to lab", config: config, user: stub_user)
      expect(req.reply).to eq("jamesbond is force deploying testuser/myapp/mybranch to lab")
    end
  end

end
