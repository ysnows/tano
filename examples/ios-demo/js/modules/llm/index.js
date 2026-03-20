/**
 * Minimal LLM module for iOS Edge.js demo
 * Mirrors Enconvo's llm module pattern using proxyFetch
 */
const { fetch: proxyFetch } = require('../../lib/swift-http-proxy');

class LLMProvider {
  constructor(config) {
    this.apiKey = config.apiKey || '';
    this.baseURL = config.baseURL || 'https://api.groq.com/openai/v1';
    this.model = config.model || 'openai/gpt-oss-120b';
    this.temperature = config.temperature || 0.7;
    this.maxTokens = config.maxTokens || 1024;
  }

  async chat(messages, options = {}) {
    const response = await proxyFetch(this.baseURL + '/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + this.apiKey,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: options.model || this.model,
        messages,
        temperature: options.temperature || this.temperature,
        max_completion_tokens: options.maxTokens || this.maxTokens,
        stream: false
      })
    });

    const data = await response.json();
    if (data.error) throw new Error(data.error.message || JSON.stringify(data.error));

    return {
      content: data.choices[0].message.content,
      model: data.model,
      usage: data.usage,
      finishReason: data.choices[0].finish_reason
    };
  }

  async complete(prompt, options = {}) {
    return this.chat([{ role: 'user', content: prompt }], options);
  }
}

module.exports = { LLMProvider };
