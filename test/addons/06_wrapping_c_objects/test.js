'use strict';
const common = require('../../common');
// test.js
const addon = require(`./build/${common.buildType}/addon`);

const obj = new addon.MyObject(10);
console.log(obj.plusOne());
// Prints: 11
console.log(obj.plusOne());
// Prints: 12
console.log(obj.plusOne());
// Prints: 13
