import type { BbPluginApi } from "@get-bb/plugin-sdk";

/**
 * Orchestra Rails — the provider-neutral half of the Orchestra package.
 *
 * Orchestra's enforcement lives in hooks, and hooks are per-runtime: Claude Code
 * reads `.claude/settings.json`, Cursor reads `.cursor/hooks.json`, Codex reads
 * `.codex/hooks.json`. OpenCode, Grok and Pi have no hook surface at all, so for
 * those runtimes a rail exists only if it is in the prompt.
 *
 * BB injects `skills/<name>/SKILL.md` into EVERY provider thread. That makes this
 * plugin the one channel that reaches every runtime BB can drive. It carries the
 * rails and nothing else: no routing, no orchestrator, no fan-out authority — a
 * worker that reads these still cannot hire anyone.
 */
export default async function plugin(bb: BbPluginApi) {
  bb.log.info(
    "Orchestra rails registered — standing rails injected into every provider thread",
  );
}
