/**
 * Hello World — echo command
 * Echoes back whatever input is provided.
 */
module.exports = async function main(req) {
    const input = req.input || req.options || {};
    return {
        content: JSON.stringify(input, null, 2),
        type: 'text',
        echo: true,
    };
};
