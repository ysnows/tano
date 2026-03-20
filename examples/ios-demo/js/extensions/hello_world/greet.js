/**
 * Hello World — greet command
 * Demonstrates a simple synchronous command handler.
 */
module.exports = async function main(req) {
    const name = (req.options && req.options.name) || req.input?.name || 'World';
    return {
        content: `Hello, ${name}! 👋 from EdgeJS iOS`,
        type: 'text',
    };
};
