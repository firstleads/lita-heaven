require "lita-heaven"
require "lita/rspec"
require "webmock/rspec"

RSpec.configure do |c|
  c.filter_run_when_matching :focus
end

# A compatibility mode is provided for older plugins upgrading from Lita 3. Since this plugin
# was generated with Lita 4, the compatibility mode should be left disabled.
Lita.version_3_compatibility_mode = false
