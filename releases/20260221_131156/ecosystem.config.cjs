const appPort = Number(process.env.APP_PORT || process.env.PORT || 3001)

module.exports = {
  apps: [
    {
      name: 'template-sharptier-cms',
      cwd: '/home/template-sharptier-cms/current',
      script: 'node_modules/.bin/next',
      args: `start -p ${appPort}`,
      exec_mode: 'cluster',
      instances: 1,
      watch: false,
      max_memory_restart: '1024M',
      env: {
        NODE_ENV: 'production',
        PORT: appPort,
        APP_PORT: appPort,
      },
      env_file: '/home/template-sharptier-cms/shared/app.env',
      error_file: '/home/template-sharptier-cms/logs/pm2-error.log',
      out_file: '/home/template-sharptier-cms/logs/pm2-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
    },
  ],
}
