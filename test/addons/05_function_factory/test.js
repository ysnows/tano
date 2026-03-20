'use strict';
const common = require('../../common');
// test.js
const addon = require(`./build/${common.buildType}/addon`);

const fn = addon();
console.log(fn());
// Prints: 'hello world'
