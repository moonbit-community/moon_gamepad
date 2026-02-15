const os = require('os');
const platform = os.platform();

const pkg = 'Milky2018/gamepad';

const linkConfig = { package: pkg };
let stubCcFlags = '';

if (platform === 'darwin') {
  linkConfig.link_flags = '-framework IOKit -framework CoreFoundation';
} else if (platform === 'linux') {
  linkConfig.link_libs = ['m', 'pthread', 'dl', 'rt'];
} else if (platform === 'win32') {
  linkConfig.link_libs = [
    'user32',
    'winmm',
    'shell32',
    'ole32',
    'uuid',
    'mmdevapi',
    'avrt',
  ];
} else {
  throw new Error(`Unsupported platform: ${platform}`);
}

const output = {
  vars: { GAMEPAD_STUB_CC_FLAGS: stubCcFlags },
  link_configs: [linkConfig],
};

console.log(JSON.stringify(output));
