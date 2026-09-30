-- Run from the repo root:  lune run tests/run.luau
local process = require("@lune/process")
local H = require("./harness")

require("./guard.spec")
require("./speed.spec")
require("./data.spec")
require("./economy.spec")

print("Steal a Seed: mocked server tests\n")
local failed = H.run()
if #H.warnings > 0 then
	print("\nwarnings logged by modules:")
	for _, w in H.warnings do
		print("  " .. w)
	end
end
process.exit(if failed > 0 then 1 else 0)
