const { join } = require('path');
const { config } = require('./wdio.shared.conf');
const pathWdioConfig = require('path');
require('dotenv').config({ path: pathWdioConfig.resolve(__dirname, '../.env') });

config.suites = {
  all: [
    './tests/specs/live/**/*.spec.ts'
  ]
};

config.capabilities = [
  {
    platformName: 'iOS',
    hostname: '127.0.0.1',
    'appium:automationName': 'XCUITest',
    'appium:options': {
      deviceName: 'iPhone 14',
      platformVersion: '16.1',
      app: join(process.cwd(), './FlowCrypt.app'),
    },
  },
];

exports.config = config;
