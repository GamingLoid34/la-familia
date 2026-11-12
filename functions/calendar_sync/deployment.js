"use strict";

// Enable in a separate, reviewed release after provider secrets and live
// account tests are ready. Do not load the provider modules while disabled:
// Firebase resolves every declared secret even for a named partial deployment.
// Keep this a committed setting, so discovery and deployed runtime agree.
exports.enabled = false;
