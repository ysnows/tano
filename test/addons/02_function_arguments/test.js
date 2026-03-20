'use strict';
const common = require('../../common');
// test.js
const addon = require(`./build/${common.buildType}/addon`);

console.log('This should be eight:', addon.add(3, 5));
