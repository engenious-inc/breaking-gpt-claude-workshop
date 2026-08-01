#!/usr/bin/env node
// Interactive REPL chat against the Groq models used by this repo's evals,
// using one of the workshop bots' system prompts (prompts/<bot>.txt).
//
// Usage:
//   node scripts/chat.js <bot> [model]
//   node scripts/chat.js medibot
//   node scripts/chat.js financebot 8b
//   node scripts/chat.js mybot gptoss
//
// <bot>   medibot | financebot | mybot   (matches prompts/<bot>.txt)
// [model] 70b (default, llama-3.3-70b-versatile) | 8b (llama-3.1-8b-instant) | gptoss (openai/gpt-oss-20b)
//
// Type your message and press Enter. Ctrl+C or "exit" to quit.

const fs = require('fs');
const path = require('path');
const readline = require('readline');

const ROOT = path.join(__dirname, '..');

function loadEnv() {
  const envPath = path.join(ROOT, '.env');
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
}
loadEnv();

const MODELS = {
  '70b': 'llama-3.3-70b-versatile',
  '8b': 'llama-3.1-8b-instant',
  gptoss: 'openai/gpt-oss-20b',
};

const bot = process.argv[2];
const modelKey = process.argv[3] || '70b';

if (!bot || !MODELS[modelKey]) {
  console.error('Usage: node scripts/chat.js <medibot|financebot|mybot> [70b|8b|gptoss]');
  process.exit(1);
}

const promptPath = path.join(ROOT, 'prompts', `${bot}.txt`);
if (!fs.existsSync(promptPath)) {
  console.error(`No such prompt file: ${promptPath}`);
  process.exit(1);
}

const template = JSON.parse(fs.readFileSync(promptPath, 'utf8'));
const systemMsg = template.find((m) => m.role === 'system');
if (!systemMsg) {
  console.error(`prompts/${bot}.txt has no system message`);
  process.exit(1);
}

const model = MODELS[modelKey];
const apiKey = process.env.GROQ_API_KEY;
if (!apiKey || apiKey.includes('replace-me')) {
  console.error('GROQ_API_KEY is missing or still the placeholder in .env — run ./setup.sh or paste your key in.');
  process.exit(1);
}

const messages = [{ role: 'system', content: systemMsg.content }];

console.log(`Chatting with ${bot} (${model}). Type "exit" to quit.\n`);

const rl = readline.createInterface({ input: process.stdin, output: process.stdout, prompt: 'you> ' });
rl.prompt();

let pending = 0;

rl.on('line', async (line) => {
  const text = line.trim();
  if (!text) return rl.prompt();
  if (text === 'exit' || text === 'quit') return rl.close();

  pending++;
  messages.push({ role: 'user', content: text });

  try {
    const res = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({ model, messages, temperature: 0, max_tokens: 400 }),
    });
    const data = await res.json();
    if (!res.ok) {
      console.log(`\n[error] ${data.error?.message || res.statusText}\n`);
      messages.pop();
      return rl.prompt();
    }
    const reply = data.choices[0].message.content;
    messages.push({ role: 'assistant', content: reply });
    console.log(`\n${bot}> ${reply}\n`);
  } catch (err) {
    console.log(`\n[error] ${err.message}\n`);
    messages.pop();
  }
  pending--;
  if (!rl.closed) rl.prompt();
});

rl.on('close', () => {
  const waitForPending = () => {
    if (pending > 0) return setTimeout(waitForPending, 100);
    console.log('\nbye');
    process.exit(0);
  };
  waitForPending();
});
