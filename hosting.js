const path = require('node:path');

function loadEnvironment(root) {
  const file = process.env.ROOMS_ENV_FILE || path.join(root, '.env');
  try {
    // Panel variables win over file values; no third-party package is required.
    process.loadEnvFile(file);
  } catch (error) {
    if (error.code !== 'ENOENT' || process.env.ROOMS_ENV_FILE) throw error;
  }
}

function configuration(env, root) {
  // Allocation ports take precedence over a PORT left over from another host.
  const port = Number(env.SERVER_PORT || env.PORT || 8787);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('SERVER_PORT or PORT must be an integer from 1 to 65535');
  }
  return {
    port,
    host: env.ROOMS_BIND_HOST || '0.0.0.0',
    dataDir: path.resolve(root, env.ROOMS_ANALYTICS_DATA_DIR || env.RENDER_DISK_PATH || 'data')
  };
}

module.exports = {loadEnvironment, configuration};
