/**
 * iOS LLM Core — OpenAI-compatible HTTP client
 *
 * Uses Node.js native https.request which works on EdgeJS/JSC.
 * Supports streaming (SSE) and non-streaming responses.
 * Compatible with OpenAI, Groq, Anthropic (via OpenAI-compat endpoint), and any
 * OpenAI-compatible API.
 */

'use strict';

const https = require('https');
const http = require('http');

const PROVIDER_CONFIGS = {
    groq: {
        hostname: 'api.groq.com',
        path: '/openai/v1/chat/completions',
        port: 443,
    },
    openai: {
        hostname: 'api.openai.com',
        path: '/v1/chat/completions',
        port: 443,
    },
    anthropic: {
        hostname: 'api.anthropic.com',
        path: '/v1/messages',
        port: 443,
        isAnthropic: true,
    },
};

/**
 * Make an OpenAI-compatible chat completion request.
 *
 * @param {Object} options
 * @param {string} options.apiKey - API key
 * @param {string} options.provider - Provider name (groq, openai, anthropic)
 * @param {string} [options.baseUrl] - Custom base URL (overrides provider default)
 * @param {string} options.model - Model name
 * @param {Array} options.messages - Chat messages [{role, content}]
 * @param {boolean} [options.stream=false] - Enable streaming
 * @param {number} [options.temperature=0.7]
 * @param {number} [options.maxTokens=4096]
 * @param {string} [options.systemPrompt] - Prepended as system message
 * @returns {Promise<Object>} Response object
 */
function chatCompletion(options) {
    const {
        apiKey,
        provider = 'groq',
        baseUrl,
        model,
        messages,
        stream = false,
        temperature = 0.7,
        maxTokens = 4096,
        systemPrompt,
    } = options;

    // Build messages array
    let fullMessages = [...messages];
    if (systemPrompt && fullMessages[0]?.role !== 'system') {
        fullMessages.unshift({ role: 'system', content: systemPrompt });
    }

    // Resolve endpoint
    let config = PROVIDER_CONFIGS[provider] || PROVIDER_CONFIGS.openai;
    let hostname = config.hostname;
    let urlPath = config.path;
    let port = config.port;
    let useHttps = true;

    if (baseUrl) {
        try {
            const url = new URL(baseUrl);
            hostname = url.hostname;
            port = url.port ? parseInt(url.port) : (url.protocol === 'https:' ? 443 : 80);
            urlPath = (url.pathname === '/' ? '' : url.pathname) + config.path;
            useHttps = url.protocol === 'https:';
        } catch (e) {
            // Use default
        }
    }

    // Build request body
    let body;
    let headers;

    if (config.isAnthropic) {
        // Anthropic API format
        const systemMsg = fullMessages.find(m => m.role === 'system');
        const chatMessages = fullMessages.filter(m => m.role !== 'system');

        body = JSON.stringify({
            model,
            messages: chatMessages,
            system: systemMsg?.content || undefined,
            max_tokens: maxTokens,
            temperature,
            stream,
        });
        headers = {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(body),
            'Connection': 'close',
        };
    } else {
        // OpenAI-compatible format
        body = JSON.stringify({
            model,
            messages: fullMessages,
            max_completion_tokens: maxTokens,
            temperature,
            stream,
        });
        headers = {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(body),
            'Connection': 'close',
        };
    }

    return new Promise((resolve, reject) => {
        const reqModule = useHttps ? https : http;
        const req = reqModule.request({
            hostname,
            port,
            path: urlPath,
            method: 'POST',
            headers,
            agent: false,
        }, (res) => {
            if (stream) {
                resolve({ stream: res, statusCode: res.statusCode, isAnthropic: config.isAnthropic });
            } else {
                let data = '';
                res.on('data', c => data += c);
                res.on('end', () => {
                    try {
                        const parsed = JSON.parse(data);
                        if (parsed.error) {
                            reject(new Error(parsed.error.message || JSON.stringify(parsed.error)));
                            return;
                        }

                        if (config.isAnthropic) {
                            resolve({
                                content: parsed.content?.[0]?.text || '',
                                model: parsed.model,
                                usage: parsed.usage,
                            });
                        } else {
                            resolve({
                                content: parsed.choices?.[0]?.message?.content || '',
                                model: parsed.model,
                                usage: parsed.usage,
                            });
                        }
                    } catch (e) {
                        reject(new Error(`Parse error: ${e.message}\nBody: ${data.substring(0, 200)}`));
                    }
                });
            }
        });

        req.on('error', reject);
        req.write(body);
        req.end();
    });
}

/**
 * Parse an SSE stream and yield content deltas.
 *
 * @param {IncomingMessage} stream - HTTP response stream
 * @param {boolean} isAnthropic - Use Anthropic SSE format
 * @returns {AsyncGenerator<{content: string, model?: string, done?: boolean}>}
 */
async function* parseSSEStream(stream, isAnthropic = false) {
    let buffer = '';

    for await (const chunk of stream) {
        buffer += chunk.toString();
        const lines = buffer.split('\n');
        buffer = lines.pop() || ''; // Keep incomplete line

        for (const line of lines) {
            if (!line.startsWith('data: ')) continue;
            const data = line.slice(6).trim();

            if (data === '[DONE]') {
                yield { content: '', done: true };
                return;
            }

            try {
                const parsed = JSON.parse(data);

                if (isAnthropic) {
                    if (parsed.type === 'content_block_delta') {
                        yield { content: parsed.delta?.text || '', model: parsed.model };
                    } else if (parsed.type === 'message_stop') {
                        yield { content: '', done: true };
                        return;
                    }
                } else {
                    const delta = parsed.choices?.[0]?.delta?.content || '';
                    const model = parsed.model;
                    const finishReason = parsed.choices?.[0]?.finish_reason;

                    if (delta) {
                        yield { content: delta, model };
                    }
                    if (finishReason) {
                        yield { content: '', done: true };
                        return;
                    }
                }
            } catch (e) {
                // Skip unparseable lines
            }
        }
    }
}

module.exports = { chatCompletion, parseSSEStream, PROVIDER_CONFIGS };
