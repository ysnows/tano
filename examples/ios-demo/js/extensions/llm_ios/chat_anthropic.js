/**
 * Anthropic LLM Provider for iOS
 */
'use strict';
const { chatCompletion } = require('./llm-core');

module.exports = async function main(req) {
    const options = req.options || {};
    return chatCompletion({
        apiKey: options.api_key || process.env.ANTHROPIC_API_KEY || '',
        provider: 'anthropic',
        model: options.model || options.modelName || 'claude-sonnet-4-6',
        messages: options.messages || [{ role: 'user', content: options.input_text || '' }],
        stream: false,
        temperature: parseFloat(options.temperature || '0.7'),
        maxTokens: parseInt(options.max_tokens || '4096'),
        systemPrompt: options.system_prompt,
    });
};
