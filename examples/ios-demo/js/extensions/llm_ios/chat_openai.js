/**
 * OpenAI LLM Provider for iOS
 */
'use strict';
const { chatCompletion } = require('./llm-core');

module.exports = async function main(req) {
    const options = req.options || {};
    return chatCompletion({
        apiKey: options.api_key || process.env.OPENAI_API_KEY || '',
        provider: 'openai',
        baseUrl: options.base_url || undefined,
        model: options.model || options.modelName || 'gpt-4o-mini',
        messages: options.messages || [{ role: 'user', content: options.input_text || '' }],
        stream: false,
        temperature: parseFloat(options.temperature || '0.7'),
        maxTokens: parseInt(options.max_tokens || '4096'),
        systemPrompt: options.system_prompt,
    });
};
