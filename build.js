const os = require('os');
const { execFileSync } = require('child_process');
const platform = os.platform();

const pkg = 'Milky2018/gamepad';

const linkConfig = { package: pkg };
let stubCcFlags = '';

if (platform === 'darwin') {
  const sdkPath = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], {
    encoding: 'utf8',
  }).trim();
  linkConfig.link_flags =
    `${sdkPath}/System/Library/Frameworks/IOKit.framework/IOKit.tbd ` +
    `${sdkPath}/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation.tbd`;
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
