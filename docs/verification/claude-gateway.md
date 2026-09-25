# Claude gateway (CLIProxyAPI) verification

Audience: maintainer verification.

This record supports the `--gateway cliproxy` contract owned by [`../configuration.md`](../configuration.md) ("Claude gateway (CLIProxyAPI)") and the harness facts in the [Claude adapter reference](../../.agents/skills/harness-adapters/references/harness/claude.md#cliproxyapi-gateway).
It records only what must be re-established when Claude Code, CLIProxyAPI, or the launch shape in `bin/fm-claude-gateway-lib.sh` changes: which model names a gateway worker sends through the proxy, how effort arrives, and that a launch without the gateway stays on the subscription.
Deterministic coverage of the refusals, the settings merge, the model-role mapping, the credential scrub, and the recorded `gateway=` field lives in `tests/fm-spawn-dispatch-profile.test.sh`, `tests/fm-control-relaunch.test.sh`, `tests/fm-bootstrap.test.sh`, and `tests/fm-dispatch-resolve.test.sh`.

## Setup

Verified 2026-09-25 on Claude Code 2.1.282 against CLIProxyAPI listening on `127.0.0.1:8317`, with the fleet's Anthropic account signed out of the proxy.
A logging relay listened on `127.0.0.1:18317`, forwarded every byte to the proxy, and logged one line per request on the client-to-proxy direction: the request line, which auth header names were present (never their values), the `anthropic-beta` header, and the `model`, `thinking`, `output_config`, `max_tokens`, message-count, and tool-count fields of each JSON body.
A test copy of the shared settings file named the relay as its base URL and kept the real `apiKeyHelper` command, so the worker authenticated with the real key while every request was observed.
The launch was the command `bin/fm-spawn.sh --harness claude --model gpt-6-sol --effort high --gateway cliproxy` produces, composed from the library's own `fm_claude_gateway_scrub_flags`, `fm_claude_gateway_env_prefix`, and `fm_claude_gateway_settings` with `HOME` pointed at the test copy, and run interactively in a disposable `tmux -L fmgw` server from the task worktree.
Re-verified after the review fix: re-run 2026-09-25 on Claude Code 2.1.282 with the launch shape that carries the model roles both in the process environment and in the merged settings `env`, using the library at the reviewed head and a test copy of the settings file that also carried a decoy `env.ANTHROPIC_DEFAULT_OPUS_MODEL` value; the merge replaced that decoy with `gpt-6-sol` in the launch's settings `env`.
The relay again saw `HEAD /api/hello` and then five `POST /v1/messages?beta=true` requests, all with model `gpt-6-sol` and in the same order and shapes as the table below (title generation with 1 message and 0 tools, the foreground turn with 29 tools, the general-purpose subagent with 17 tools, then the two foreground continuations), each with `output_config.effort=high`, `thinking: adaptive` on the conversational requests, and both the `authorization` and `x-api-key` header names; no `claude-*` model name was sent.
The pane header again read `gpt-6-sol with high effort · API Usage Billing`, the subagent finished in 3 seconds, and the worker answered `PONG` then `DONE`.
Two additions kept the probe from disturbing the fleet: `--setting-sources user,project` so the worktree's own per-task Stop hooks did not fire, and `FM_ALLOW_SUBAGENT=1` so the tracked subagent guard admitted the Agent call.
The prompt asked for exactly one Agent call (`general-purpose`, "Reply with exactly the word PONG and nothing else") and then the words PONG and DONE.

## Model names the proxy saw

The pane header read `gpt-6-sol with high effort · API Usage Billing`, the subagent finished in 4 seconds, and the worker answered `PONG` then `DONE`.
The relay log for that session, in order:

| Request | Model | Effort form | Messages | Tools | What it was |
| --- | --- | --- | --- | --- | --- |
| `HEAD /api/hello` | - | - | - | - | connectivity probe, no auth header |
| `POST /v1/messages?beta=true` | `gpt-6-sol` | `output_config.effort=high` | 1 | 0 | conversation title, a JSON-schema `{title}` request: the haiku-role background call |
| `POST /v1/messages?beta=true` | `gpt-6-sol` | `thinking: adaptive`, `output_config.effort=high` | 2 | 29 | the foreground turn |
| `POST /v1/messages?beta=true` | `gpt-6-sol` | `thinking: adaptive`, `output_config.effort=high` | 2 | 17 | the general-purpose subagent |
| `POST /v1/messages?beta=true` | `gpt-6-sol` | `thinking: adaptive`, `output_config.effort=high` | 4 | 29 | the foreground turn after the subagent |
| `POST /v1/messages?beta=true` | `gpt-6-sol` | `thinking: adaptive`, `output_config.effort=high` | 6 | 29 | the final reply |

Zero `claude-*` model names were sent.
On 2.1.282, `ANTHROPIC_DEFAULT_HAIKU_MODEL` and `CLAUDE_CODE_SUBAGENT_MODEL` are therefore honored with `ANTHROPIC_BASE_URL` set through the settings file's `env`, which is the case upstream issue anthropics/claude-code#92050 reported as ignored on 2.1.260; re-run this probe after a Claude Code upgrade before trusting the mapping.
The title call is the only haiku-role background call this run exercised: compaction and the permission classifier did not run (bypass mode, short conversation), so those roles remain unobserved.
Every `POST` carried both an `authorization` and an `x-api-key` header, and the worker showed the banner `claude.ai connectors are disabled because ANTHROPIC_API_KEY or another auth source is set and takes precedence over your claude.ai login`, which is the helper key outranking the claude.ai login as intended.

## How effort arrives

`--effort high` reached the proxy on every `POST` as `output_config: {"effort": "high"}`, never as a top-level `effort` field, with `thinking: {"type": "adaptive"}` on the conversational requests and `effort-2025-11-24` among the `anthropic-beta` values.
What the proxy makes of that for a non-Anthropic vendor is the proxy's contract, not Firstmate's.

## A launch without the gateway stays on the subscription

In the same tmux session, with the pane shell exporting `ANTHROPIC_BASE_URL=http://127.0.0.1:18317` plus sentinel `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` values, the no-gateway launch shape (`--model haiku`, no `--gateway`) started as `Haiku 4.5 · Claude Max`.
Its Bash tool printed `BASE=unset KEY=unset TOKEN=unset`, and the relay recorded zero requests during that run.
That run used an earlier no-gateway shape that also unset `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_API_KEY`; the current no-gateway shape unsets only `ANTHROPIC_BASE_URL`, which is the variable that kept that worker off the relay, and leaves the pane's own credentials to Claude Code as they were before the gateway existed.
This section has not been re-run with the current shape.

## Proxy model listing

`GET /v1/models` with the helper key listed 43 models whose `owned_by` was one of `antigravity`, `openai`, and `xai`; each entry carried only `created`, `id`, `object`, and `owned_by`, so no context-window field exists to source `CLAUDE_CODE_MAX_CONTEXT_TOKENS` from.
The same request without the key answered 401.

## Refreshing this record

1. Start a relay in front of the proxy that logs request model and effort fields, and write a settings copy naming it under a scratch `HOME`.
2. Compose the launch from `bin/fm-claude-gateway-lib.sh` with that `HOME`, run it in a disposable tmux server from a trusted worktree with `--setting-sources user,project` and `FM_ALLOW_SUBAGENT=1`, and prompt for one Agent call.
3. Record every model name the relay saw, the effort form, and the auth header names; then repeat the no-gateway shape with `ANTHROPIC_BASE_URL` naming the relay in the pane shell and confirm the relay saw nothing and the worker's Bash reports it unset.
4. Kill the tmux server and the relay; the key must not appear in any artifact.
