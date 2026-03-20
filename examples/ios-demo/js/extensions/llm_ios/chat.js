/**
 * iOS Chat Command — Full chat with streaming via UDS
 *
 * This is a complete chat command that:
 * 1. Reads user input from request options
 * 2. Calls configured LLM provider (Groq/OpenAI/Anthropic)
 * 3. Streams response chunks back to Swift via Commander
 * 4. Returns final result
 */

'use strict';

const { chatCompletion, parseSSEStream } = require('./llm-core');
let Commander;
try { Commander = require('@enconvo/api').Commander; } catch (e) {}

module.exports = async function main(req) {
    const options = req.options || {};
    const context = req.context || {};
    const input = options.input_text || options.prompt || req.input?.text || '';

    if (!input) {
        return { content: 'No input provided', type: 'text', status: 400 };
    }

    const apiKey = options.api_key || process.env.GROQ_API_KEY || '';
    const provider = options.provider || 'groq';
    const model = options.model || (provider === 'groq' ? 'llama-3.3-70b-versatile' : 'gpt-4o-mini');
    const baseUrl = options.base_url || '';
    const systemPrompt = options.system_prompt || 'You are a helpful assistant.';
    const temperature = parseFloat(options.temperature || '0.7');
    const maxTokens = parseInt(options.max_tokens || '4096');

    if (!apiKey) {
        return { content: 'No API key configured. Set api_key in preferences.', type: 'text', status: 401 };
    }

    // Build messages from conversation history or single message
    const messages = options.messages || [{ role: 'user', content: input }];

    try {
        // Streaming mode
        const response = await chatCompletion({
            apiKey,
            provider,
            baseUrl: baseUrl || undefined,
            model,
            messages,
            stream: true,
            temperature,
            maxTokens,
            systemPrompt,
        });

        if (response.statusCode !== 200) {
            // Read error body
            let errBody = '';
            for await (const chunk of response.stream) errBody += chunk.toString();
            try {
                const errJson = JSON.parse(errBody);
                return { content: `API Error: ${errJson.error?.message || errBody}`, type: 'text', status: response.statusCode };
            } catch (e) {
                return { content: `API Error (${response.statusCode}): ${errBody.substring(0, 200)}`, type: 'text', status: response.statusCode };
            }
        }

        let fullContent = '';
        let responseModel = model;

        for await (const delta of parseSSEStream(response.stream, response.isAnthropic)) {
            if (delta.done) break;
            if (delta.content) {
                fullContent += delta.content;
                if (delta.model) responseModel = delta.model;

                // Stream chunk to Swift via Commander
                if (Commander) {
                    Commander.send('responseStream', {
                        content: fullContent,
                        type: 'text',
                        action: 'stream',
                        model: responseModel,
                    }, context);
                }
            }
        }

        return {
            content: fullContent,
            type: 'text',
            model: responseModel,
        };
    } catch (err) {
        return { content: `Error: ${err.message}`, type: 'text', status: 500 };
    }
};
