/**
 * Hello World — stream_demo command
 * Demonstrates streaming responses back to Swift via Commander.
 */
const Commander = require('../../lib/commander-ios');

module.exports = async function main(req) {
    const context = req.context;
    const words = ['Hello', ' from', ' EdgeJS', ' iOS!', ' This', ' is', ' a', ' streaming', ' demo.'];

    for (const word of words) {
        Commander.sendStream({ content: word, type: 'text' }, context);
        // Simulate processing delay
        await new Promise(resolve => setTimeout(resolve, 200));
    }

    return {
        content: words.join(''),
        type: 'text',
    };
};
