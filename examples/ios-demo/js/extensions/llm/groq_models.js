// Auto-generated banner
"use strict";
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/groq_models.ts
var groq_models_exports = {};
__export(groq_models_exports, {
  default: () => main
});
module.exports = __toCommonJS(groq_models_exports);
var import_api = require("@enconvo/api");
var groqModelsData = [
  // Production Models - intended for use in production environments
  // Meta Llama Models
  {
    title: "Llama 3.1 8B Instant",
    value: "llama-3.1-8b-instant",
    providerName: "Meta",
    inputPrice: 0.05,
    outputPrice: 0.08,
    speed: 5,
    // Very fast
    intelligence: 3,
    context: 131072,
    // 131k context window
    maxTokens: 131072
    // 131k max completion tokens
  },
  {
    title: "Llama 3.3 70B Versatile",
    value: "llama-3.3-70b-versatile",
    providerName: "Meta",
    inputPrice: 0.59,
    outputPrice: 0.79,
    speed: 4,
    // Fast
    intelligence: 4,
    context: 131072,
    // 131k context window
    maxTokens: 32768
    // 32k max completion tokens
  },
  {
    title: "Meta Llama Guard 4 12B",
    value: "meta-llama/llama-guard-4-12b",
    providerName: "Meta",
    inputPrice: 0.2,
    outputPrice: 0.2,
    speed: 4,
    // Moderate-Fast
    intelligence: 3,
    context: 131072,
    // 131k context window
    maxTokens: 1024
    // 1k max completion tokens
  },
  // OpenAI Whisper Models (Audio transcription)
  {
    title: "Whisper Large V3",
    value: "whisper-large-v3",
    providerName: "OpenAI",
    inputPrice: 0,
    outputPrice: 0,
    speed: 4,
    intelligence: 4,
    context: 0,
    // Audio model - no text context
    maxTokens: 0
    // Audio model - no text tokens
  },
  {
    title: "Whisper Large V3 Turbo",
    value: "whisper-large-v3-turbo",
    providerName: "OpenAI",
    inputPrice: 0,
    outputPrice: 0,
    speed: 5,
    // Turbo version is faster
    intelligence: 4,
    context: 0,
    // Audio model - no text context
    maxTokens: 0
    // Audio model - no text tokens
  },
  // Preview Models - for evaluation purposes only, not for production
  // DeepSeek Models
  {
    title: "DeepSeek R1 Distill Llama 70B",
    value: "deepseek-r1-distill-llama-70b",
    providerName: "DeepSeek / Meta",
    inputPrice: 0.75,
    outputPrice: 0.99,
    speed: 4,
    // Fast
    intelligence: 4,
    context: 131072,
    // 131k context window
    maxTokens: 131072
    // 131k max completion tokens
  },
  // Meta Llama 4 Models (Preview)
  {
    title: "Meta Llama 4 Maverick 17B 128E Instruct",
    value: "meta-llama/llama-4-maverick-17b-128e-instruct",
    providerName: "Meta",
    inputPrice: 0.2,
    outputPrice: 0.6,
    speed: 4,
    // Fast
    intelligence: 4,
    context: 131072,
    // 131k context window
    maxTokens: 8192
    // 8k max completion tokens
  },
  {
    title: "Meta Llama 4 Scout 17B 16E Instruct",
    value: "meta-llama/llama-4-scout-17b-16e-instruct",
    providerName: "Meta",
    inputPrice: 0.11,
    outputPrice: 0.34,
    speed: 4,
    // Fast
    intelligence: 4,
    context: 131072,
    // 131k context window
    maxTokens: 8192
    // 8k max completion tokens
  },
  // Meta Llama Prompt Guard Models
  {
    title: "Meta Llama Prompt Guard 2 22M",
    value: "meta-llama/llama-prompt-guard-2-22m",
    providerName: "Meta",
    inputPrice: 0,
    outputPrice: 0,
    speed: 5,
    // Very fast (small model)
    intelligence: 2,
    context: 512,
    // 512 context window
    maxTokens: 512
    // 512 max completion tokens
  },
  {
    title: "Meta Llama Prompt Guard 2 86M",
    value: "meta-llama/llama-prompt-guard-2-86m",
    providerName: "Meta",
    inputPrice: 0,
    outputPrice: 0,
    speed: 5,
    // Very fast (small model)
    intelligence: 2,
    context: 512,
    // 512 context window
    maxTokens: 512
    // 512 max completion tokens
  },
  // Moonshot AI Kimi Models
  {
    title: "Moonshot AI Kimi K2 Instruct",
    value: "moonshotai/kimi-k2-instruct",
    providerName: "Moonshot AI",
    inputPrice: 1,
    outputPrice: 3,
    speed: 3,
    // Moderate
    intelligence: 5,
    context: 131072,
    // 131k context window
    maxTokens: 16384
    // 16k max completion tokens
  },
  // OpenAI GPT OSS Models
  {
    title: "OpenAI GPT OSS 120B",
    value: "openai/gpt-oss-120b",
    providerName: "OpenAI",
    inputPrice: 0.15,
    outputPrice: 0.75,
    speed: 4,
    // Fast
    intelligence: 4,
    context: 131072,
    // 131k context window
    maxTokens: 32766,
    // 32k max completion tokens
    preferences: [
      {
        "name": "reasoning_effort",
        "description": "Applicable to reasoning models only, this option controls the reasoning token length.",
        "type": "dropdown",
        "required": false,
        "title": "Reasoning Effort",
        "default": "low",
        "data": [
          {
            "title": "low",
            "value": "low",
            "description": "Favors speed and economical token usage with basic reasoning"
          },
          {
            "title": "medium",
            "value": "medium",
            "description": "Balance between speed and reasoning accuracy (default)"
          },
          {
            "title": "high",
            "value": "high",
            "description": "Favors more complete reasoning with higher token usage"
          }
        ]
      }
    ]
  },
  {
    title: "OpenAI GPT OSS 20B",
    value: "openai/gpt-oss-20b",
    providerName: "OpenAI",
    inputPrice: 0.1,
    outputPrice: 0.5,
    speed: 5,
    // Very fast
    intelligence: 3,
    context: 131072,
    // 131k context window
    maxTokens: 32768,
    // 32k max completion tokens
    preferences: [
      {
        "name": "reasoning_effort",
        "description": "Applicable to reasoning models only, this option controls the reasoning token length.",
        "type": "dropdown",
        "required": false,
        "title": "Reasoning Effort",
        "default": "low",
        "data": [
          {
            "title": "low",
            "value": "low",
            "description": "Favors speed and economical token usage with basic reasoning"
          },
          {
            "title": "medium",
            "value": "medium",
            "description": "Balance between speed and reasoning accuracy (default)"
          },
          {
            "title": "high",
            "value": "high",
            "description": "Favors more complete reasoning with higher token usage"
          }
        ]
      }
    ]
  },
  // PlayAI TTS Models
  {
    title: "PlayAI TTS",
    value: "playai-tts",
    providerName: "PlayAI",
    inputPrice: 0,
    outputPrice: 0,
    speed: 4,
    intelligence: 3,
    context: 8192,
    // 8k context window
    maxTokens: 8192
    // 8k max completion tokens
  },
  {
    title: "PlayAI TTS Arabic",
    value: "playai-tts-arabic",
    providerName: "PlayAI",
    inputPrice: 0,
    outputPrice: 0,
    speed: 4,
    intelligence: 3,
    context: 8192,
    // 8k context window
    maxTokens: 8192
    // 8k max completion tokens
  },
  // Alibaba Cloud Qwen Models
  {
    title: "Qwen 3 32B",
    value: "qwen/qwen3-32b",
    providerName: "Alibaba Cloud",
    inputPrice: 0.29,
    outputPrice: 0.59,
    speed: 4,
    // Fast
    intelligence: 4,
    context: 131072,
    // 131k context window
    maxTokens: 40960
    // 40k max completion tokens
  }
];
async function fetchModels(options) {
  console.log("fetchModels", options);
  try {
    if (!options.url || !options.api_key) {
      throw new Error("URL and API key are required");
    }
    const resp = await fetch(options.url, {
      headers: {
        Authorization: `Bearer ${options.api_key}`
      }
    });
    if (!resp.ok) {
      throw new Error(`API request failed with status ${resp.status}`);
    }
    const data = await resp.json();
    const result = data.data.filter(
      (item) => !item.id.includes("whisper") && !item.id.includes("tts") && !item.id.includes("distil-whisper")
    ).map((item) => {
      const modelData = groqModelsData.find(
        (model) => model.value === item.id || item.id.includes(model.value) || model.value.includes(item.id)
      );
      const visionEnable = item.id.includes("vision") || item.id.includes("llava");
      const toolUse = item.id.includes("tool-use") || !item.id.includes("guard");
      return {
        title: modelData?.title || item.id,
        value: item.id,
        context: modelData?.context || item.context_window || 8192,
        maxTokens: modelData?.maxTokens || item.max_completion_tokens || 8192,
        inputPrice: modelData?.inputPrice || 0,
        outputPrice: modelData?.outputPrice || 0,
        toolUse,
        visionEnable,
        visionImageCountLimit: 1,
        systemMessageEnable: !visionEnable,
        // Vision models typically don't support system messages
        speed: modelData?.speed || 3,
        // Default speed rating
        intelligence: modelData?.intelligence || 3
        // Default intelligence rating
      };
    });
    return result;
  } catch (error) {
    console.error("Error fetching models:", error);
    return [];
  }
}
async function main(req) {
  const options = await req.json();
  const credentials = options.credentials;
  options.api_key = credentials.apiKey;
  let url;
  url = credentials.baseUrl.endsWith("/") ? credentials.baseUrl : `${credentials.baseUrl}/`;
  url = `${url}models`;
  options.url = url;
  const modelCache = new import_api.ListCache(fetchModels);
  const models = await modelCache.getList(options);
  return JSON.stringify(models);
}
const { Commander: CommandDefaultCommander } = require('@enconvo/api');
CommandDefaultCommander.addViewListener();
CommandDefaultCommander.addClickListener(module.exports.default, 'start');
