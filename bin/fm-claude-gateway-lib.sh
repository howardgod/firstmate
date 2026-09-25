#!/usr/bin/env bash
# fm-claude-gateway-lib.sh - the single owner of the opt-in CLIProxyAPI
# gateway for Claude Code workers: the accepted gateway names, the shared
# settings file a gateway launch loads, every refusal, the per-launch
# --settings merge, the model-mapping environment a gateway launch carries,
# and the endpoint variables a Claude launch sheds.
#
# docs/configuration.md "Claude gateway (CLIProxyAPI)" owns the operator-facing
# contract. Sourced by bin/fm-spawn.sh and bin/fm-control.sh; bin/fm-bootstrap.sh
# and bin/fm-dispatch-resolve.sh source it for FM_CLAUDE_GATEWAY_ANTHROPIC_MODEL_RE.
#
# Why: Anthropic models keep using Claude Code's own subscription, while a
# dispatch profile may send another vendor's model through the local
# CLIProxyAPI from the same Claude Code binary, so the fleet keeps one coding
# agent. The proxy is selected per launch, never inherited from the supervisor:
# every Claude launch sheds ANTHROPIC_BASE_URL, a gateway launch also sheds
# ANTHROPIC_AUTH_TOKEN and ANTHROPIC_API_KEY so no inherited key outranks the
# helper, and a gateway launch re-establishes the base URL and key helper only
# through the shared settings file, so a key rotation or URL change edits one
# file. A launch without a gateway leaves the pane's own credentials alone.
#
# Settings file: $HOME/.claude/cliproxy-settings.json, a Claude Code settings
# document whose `env.ANTHROPIC_BASE_URL` names the proxy and whose
# `apiKeyHelper` command prints the key (for example
# `cat ~/.claude/cliproxy-api-key`). The key itself never enters this library,
# a launch command, a task record, or a status line; only the file path and the
# helper command do, and the merged settings JSON that rides the launch
# command carries exactly those.
#
# Refusals (all before any endpoint, worktree, or record exists):
#   - a gateway other than cliproxy
#   - any harness other than claude, and a raw launch command, which cannot
#     receive the merged --settings
#   - a --secondmate spawn: a secondmate's profile comes from
#     config/secondmate-harness, which carries no gateway token
#   - no model, or an Anthropic model (a claude prefix or one of Claude Code's
#     own aliases, matched case-insensitively by
#     FM_CLAUDE_GATEWAY_ANTHROPIC_MODEL_RE): an Anthropic model never goes
#     through the proxy (Anthropic ToS), and Claude Code's default model is an
#     Anthropic model; bin/fm-bootstrap.sh and bin/fm-dispatch-resolve.sh test
#     profiles against the same pattern
#   - a missing, unreadable, non-JSON settings file, or one lacking a
#     non-empty env.ANTHROPIC_BASE_URL string or apiKeyHelper string
#   - a settings file whose env carries ANTHROPIC_API_KEY,
#     ANTHROPIC_AUTH_TOKEN, or CLAUDE_CODE_OAUTH_TOKEN: the whole file rides
#     the launch command, so the key belongs behind apiKeyHelper
#   - jq absent, since the merge needs it
#
# A gateway launch maps Claude Code's model roles (FM_CLAUDE_GATEWAY_MODEL_ROLES:
# ANTHROPIC_DEFAULT_HAIKU_MODEL, ANTHROPIC_DEFAULT_SONNET_MODEL,
# ANTHROPIC_DEFAULT_OPUS_MODEL, and CLAUDE_CODE_SUBAGENT_MODEL) onto the
# profile model in two places: the launch-prefix environment and the merged
# settings env, where they are applied after the shared file so a role the
# file names never wins over the profile model. Claude Code's background calls
# and subagents then ask the proxy for the chosen model instead of a built-in
# Anthropic model name (docs/verification/claude-gateway.md records what the
# installed version actually sends).

# The endpoint a Claude worker must never inherit (a supervisor switched to
# the proxy by hand would otherwise leak its base URL into a subscription
# worker), and the credentials a gateway worker must never inherit (they would
# outrank the helper key and reach the proxy).
FM_CLAUDE_GATEWAY_SCRUB="ANTHROPIC_BASE_URL"
FM_CLAUDE_GATEWAY_CREDENTIAL_SCRUB="ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY"

# An Anthropic model, tested case-insensitively: a claude prefix, or one of
# Claude Code's own aliases with or without the [1m] suffix.
FM_CLAUDE_GATEWAY_ANTHROPIC_MODEL_RE='^(claude|(default|opus|sonnet|haiku|opusplan|best)(\[1m\])?$)'

# Claude Code's model roles a gateway launch maps onto the profile model.
FM_CLAUDE_GATEWAY_MODEL_ROLES="ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL CLAUDE_CODE_SUBAGENT_MODEL"

fm_claude_gateway_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

# fm_claude_gateway_settings_path
# Prints the shared settings file a gateway launch loads.
fm_claude_gateway_settings_path() {
  printf '%s\n' "${HOME:?HOME is unset}/.claude/cliproxy-settings.json"
}

# fm_claude_gateway_scrub_flags <gateway>
# Prints the `env` -u flags a Claude launch carries: the endpoint above on
# every launch, plus the credentials above when <gateway> is non-empty.
fm_claude_gateway_scrub_flags() {
  local var flags='' vars=$FM_CLAUDE_GATEWAY_SCRUB
  [ -z "$1" ] || vars="$vars $FM_CLAUDE_GATEWAY_CREDENTIAL_SCRUB"
  for var in $vars; do
    flags="$flags${flags:+ }-u $var"
  done
  printf '%s\n' "$flags"
}

# fm_claude_gateway_validate <gateway> <harness> <kind> <model> <raw-launch 0|1>
# Returns 0 when a gateway launch may proceed; otherwise prints one error line
# and returns 1. An empty or `none` gateway always passes.
fm_claude_gateway_validate() {
  local gateway=$1 harness=$2 kind=$3 model=$4 raw=$5 settings
  case "$gateway" in
  '' | none) return 0 ;;
  cliproxy) ;;
  *)
    echo "error: --gateway must be cliproxy (got '$gateway')" >&2
    return 1
    ;;
  esac
  if [ "$harness" != claude ]; then
    echo "error: --gateway cliproxy applies only to --harness claude; harness '$harness' has no proxy contract" >&2
    return 1
  fi
  if [ "$raw" = 1 ]; then
    echo "error: --gateway cliproxy needs the canonical claude launch so the proxy settings ride its --settings; a raw launch command cannot carry them" >&2
    return 1
  fi
  if [ "$kind" = secondmate ]; then
    echo "error: --gateway cliproxy is for crewmate and scout spawns only; a secondmate's profile comes from config/secondmate-harness, which carries no gateway" >&2
    return 1
  fi
  if [ -z "$model" ] || [ "$model" = default ]; then
    echo "error: --gateway cliproxy needs an explicit non-Anthropic --model: Claude Code's default model is an Anthropic model, which never goes through the proxy" >&2
    return 1
  fi
  if [[ "$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')" =~ $FM_CLAUDE_GATEWAY_ANTHROPIC_MODEL_RE ]]; then
    echo "error: --gateway cliproxy refuses model '$model': Anthropic models stay on Claude Code's own subscription and never go through CLIProxyAPI (Anthropic terms of service)" >&2
    return 1
  fi
  settings=$(fm_claude_gateway_settings_path)
  if [ ! -f "$settings" ]; then
    echo "error: --gateway cliproxy needs the shared proxy settings file $settings (env.ANTHROPIC_BASE_URL plus apiKeyHelper); it is missing" >&2
    return 1
  fi
  if [ ! -r "$settings" ]; then
    echo "error: --gateway cliproxy cannot read the shared proxy settings file $settings" >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: --gateway cliproxy needs jq to merge $settings into the launch settings" >&2
    return 1
  fi
  if ! jq -e '
      type == "object"
      and (.env | type) == "object"
      and (.env.ANTHROPIC_BASE_URL | type) == "string" and (.env.ANTHROPIC_BASE_URL | length) > 0
      and (.apiKeyHelper | type) == "string" and (.apiKeyHelper | length) > 0
    ' "$settings" >/dev/null 2>&1; then
    echo "error: --gateway cliproxy needs $settings to be a JSON object with a non-empty env.ANTHROPIC_BASE_URL string and a non-empty apiKeyHelper string" >&2
    return 1
  fi
  if jq -e '.env | has("ANTHROPIC_API_KEY") or has("ANTHROPIC_AUTH_TOKEN") or has("CLAUDE_CODE_OAUTH_TOKEN")' "$settings" >/dev/null 2>&1; then
    echo "error: --gateway cliproxy refuses $settings: its env carries ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN, or CLAUDE_CODE_OAUTH_TOKEN, and a credential in the file would enter the launch command; the key belongs behind apiKeyHelper" >&2
    return 1
  fi
  return 0
}

# fm_claude_gateway_settings <base-settings-json> <model>
# Prints the launch's inline --settings JSON: the base worker settings with
# the shared settings file merged over them and the model roles set to the
# profile model last, so the file never overrides them (compact, one line).
# Validate first.
fm_claude_gateway_settings() {
  local base=$1 model=$2 settings
  settings=$(fm_claude_gateway_settings_path)
  jq -c --argjson base "$base" --arg m "$model" --arg roles "$FM_CLAUDE_GATEWAY_MODEL_ROLES" \
    '$base * . * {env: ($roles | split(" ") | map({key: ., value: $m}) | from_entries)}' "$settings"
}

# fm_claude_gateway_env_prefix <model>
# Prints the launch-prefix assignments that map Claude Code's built-in model
# roles onto the proxied model.
fm_claude_gateway_env_prefix() {
  local role quoted
  quoted=$(fm_claude_gateway_quote "$1")
  for role in $FM_CLAUDE_GATEWAY_MODEL_ROLES; do
    printf '%s=%s ' "$role" "$quoted"
  done
  printf '\n'
}
