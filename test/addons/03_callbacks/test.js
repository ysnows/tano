'use strict';
const common = require('../../common');
// test.js
const addon = require(`./build/${common.buildType}/addon`);

addon((msg) => {
  console.log(msg);
// Prints: 'hello world'
});
