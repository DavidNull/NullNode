// Load profile for the NullNode gateway. Two things a generic HTTP test would
// not measure:
//
//   1. TTFT. With stream:true, k6's `waiting` timing is a decent proxy for
//      time-to-first-token. Total duration is dominated by output length.
//   2. Cache behaviour. One scenario replays a fixed prompt, the other varies
//      it. The two latency curves diverging is the cache working.
//
// Run: make load-test

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const GATEWAY = __ENV.GATEWAY || 'http://gateway.nullnode.localhost:8080';
const API_KEY = __ENV.API_KEY;
const MODEL = __ENV.MODEL || 'llama3.2';

if (!API_KEY) {
  throw new Error('API_KEY is required (a master key or a department key)');
}

const ttft = new Trend('llm_ttft', true);
const cachedTtft = new Trend('llm_ttft_cached', true);
const errors = new Rate('llm_errors');

export const options = {
  scenarios: {
    // Interactive load with a mostly cold cache.
    unique_prompts: {
      executor: 'ramping-vus',
      exec: 'uniquePrompt',
      startVUs: 1,
      stages: [
        { duration: '1m', target: 4 },
        { duration: '3m', target: 4 },
        { duration: '1m', target: 8 },
        { duration: '2m', target: 8 },
        { duration: '30s', target: 0 },
      ],
      tags: { workload: 'unique' },
    },
    // Same prompt every time: everything after the first should be a cache
    // hit, and roughly two orders of magnitude faster.
    repeated_prompt: {
      executor: 'constant-vus',
      exec: 'repeatedPrompt',
      vus: 2,
      duration: '7m30s',
      tags: { workload: 'cached' },
    },
  },
  thresholds: {
    // Calibrated for a 3B model on one consumer GPU. Re-baseline first.
    'llm_ttft{workload:unique}': ['p(95)<8000'],
    'llm_ttft_cached': ['p(95)<500'],
    llm_errors: ['rate<0.02'],
    // 429s are the governance layer working, but a flood of them means the
    // limits are below the load profile.
    'http_req_failed': ['rate<0.05'],
  },
};

const TOPICS = [
  'idempotent Terraform modules', 'Kubernetes admission control',
  'Redis eviction policies', 'GPU memory fragmentation',
  'OpenTelemetry span attributes', 'Postgres connection pooling',
  'KEDA scaler cooldowns', 'prompt injection defences',
];

function call(prompt, trend, extraTags) {
  const payload = JSON.stringify({
    model: MODEL,
    messages: [{ role: 'user', content: prompt }],
    max_tokens: 128,
    temperature: 0,
    stream: true,
  });

  const res = http.post(`${GATEWAY}/v1/chat/completions`, payload, {
    headers: {
      Authorization: `Bearer ${API_KEY}`,
      'Content-Type': 'application/json',
    },
    timeout: '300s',
    tags: extraTags,
  });

  const ok = check(res, {
    'status is 200': (r) => r.status === 200,
    'body is not empty': (r) => r.body && r.body.length > 0,
  });

  errors.add(!ok);
  if (res.status === 200) {
    trend.add(res.timings.waiting);
  }
  return res;
}

export function uniquePrompt() {
  const topic = TOPICS[Math.floor(Math.random() * TOPICS.length)];
  // The nonce keeps this off the cache path.
  const nonce = `${__VU}-${__ITER}`;
  call(`Explain ${topic} in two sentences. Request id ${nonce}.`, ttft, {
    workload: 'unique',
  });
  // Without think time this measures how fast k6 saturates a queue.
  sleep(Math.random() * 3 + 2);
}

export function repeatedPrompt() {
  call('Reply with the single word: pong', cachedTtft, { workload: 'cached' });
  sleep(1);
}

export function handleSummary(data) {
  const get = (metric, stat) =>
    (data.metrics[metric] && data.metrics[metric].values[stat]) || 0;

  const lines = [
    '',
    'NullNode gateway load test',
    '==========================',
    `requests          : ${get('http_reqs', 'count')}`,
    `error rate        : ${(get('llm_errors', 'rate') * 100).toFixed(2)}%`,
    `TTFT p95 (unique) : ${get('llm_ttft', 'p(95)').toFixed(0)} ms`,
    `TTFT p95 (cached) : ${get('llm_ttft_cached', 'p(95)').toFixed(0)} ms`,
    '',
    'If the cached p95 is not far below the unique one, the cache is not being',
    'hit - check maxmemory evictions before the TTL.',
    '',
  ];

  return {
    stdout: lines.join('\n'),
    'k6-summary.json': JSON.stringify(data, null, 2),
  };
}
