const core = require("@actions/core");

async function run() {
  try {
    // Get inputs from the action
    const rulesPath = core.getInput("rules-path") || "/rules";

    console.log(`Ting Tong Action configured with rules path: ${rulesPath}`);

    // For Docker-based actions, the main execution happens in the Docker container
    // This JavaScript runner can be used for setup or post-processing
  } catch (error) {
    core.setFailed(error.message);
  }
}

run();
