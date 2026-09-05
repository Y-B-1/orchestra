#!/usr/bin/env python3
"""Codex worker-only limits for PreToolUse.

For read-only roles this is defense in depth over the generated sandbox, which
remains the primary enforcement boundary. Read-only Bash is limited to a small
inspection-command allowlist. All worker Bash commands containing shell
expansion syntax are denied, even when quoted and harmless, because faithfully
emulating every supported shell before execution is not a sound guard boundary.
Grouping parentheses and file-descriptor duplication are part of that denied
surface because they can reopen an interactive stdin path after PreToolUse.
Installed shell, interpreter, and database REPL families must also present an
explicitly modeled noninteractive payload; unknown options fail closed.
Writable workers continue to rely on their sandbox as the authority for
filesystem isolation.
"""

import json
import os
import re
import shlex
import subprocess
import sys

WORKTREE_MUTATION = re.compile(
    r"\bworktree\b[^;&|\n]*\b(?:add|remove|move|prune|lock|unlock|repair)\b"
)
SAFE_REDIRECTS = {"/dev/null", "/dev/stdout", "/dev/stderr"}
COMMAND_PREFIX = r"(?:^|[;&|()]\s*)(?:(?:sudo|command)\s+|env(?:\s+\S+=\S+)*\s+)*"
INTERACTIVE_COMMAND = re.compile(
    r"^\s*(?:(?:sudo|command)\s+|env(?:\s+\S+=\S+)*\s+)*(?:/\S*/)?"
    r"(?:(?:ba|z|fi|da|k|t?c)?sh(?:\s+-[il]+)*|"
    r"python(?:\d+(?:\.\d+)*)?(?:\s+(?:-i|--interactive))*|"
    r"node(?:\d+(?:\.\d+)*)?(?:\s+(?:-i|--interactive))*|"
    r"(?:ruby|irb|perl|php)(?:\d+(?:\.\d+)*)?(?:\s+-i)?)\s*$"
)
SHELL_STDIN_BRIDGE = re.compile(
    COMMAND_PREFIX
    + r"(?:/\S*/)?(?:ba|z|fi|da|k)?sh\b[^;&|\n]*\s-[A-Za-z]*c\b[\s\S]*\bread\b"
)
BYPASS_MARKER = ".claude/.bypass-guards"
LEASE_REFERENCES = ("coordinator-lease.py", "codex-orchestra/coordinator-lease")
CONTROL_STATE_PATHS = ("docs/orchestra/STATE.md", ".orchestra/state.json")
FILE_REFERENCE = re.compile(
    r"(?<![A-Za-z0-9_.-])(?:/|(?:\.\.?/))?[A-Za-z0-9_.-]+"
    r"(?:/[A-Za-z0-9_.-]+)*(?![A-Za-z0-9_.-])"
)
DYNAMIC_SHELL_SYNTAX = re.compile(r"[$`*?\[\]{}~\\()]|[<>]&")
SAFE_PROGRAMS = {
    "cat",
    "head",
    "ls",
    "printf",
    "pwd",
    "readlink",
    "rg",
    "shasum",
    "stat",
    "tail",
    "wc",
}
SAFE_GIT_COMMANDS = {"diff", "log", "ls-files", "rev-parse", "show", "status"}
SHELL_PROGRAM = re.compile(r"^(?:(?:ba|z|fi|da|k)?sh|t?csh)$")
INTERPRETER_PROGRAM = re.compile(
    r"^(?:python|node|ruby|irb|perl|php|tclsh|wish)(?:\d+(?:\.\d+)*)?$"
)
DATABASE_PROGRAM = re.compile(
    r"^(?:sqlite3(?:\.\d+)*|psql(?:-?\d+(?:\.\d+)*)?)$"
)
SED_PRINT_SCRIPT = re.compile(
    r"(?:(?:\d+|\$|/[^/\n]*/)(?:,(?:\d+|\$|/[^/\n]*/))?)?[p=q]"
)


def repository_root(payload):
    explicit = os.environ.get("CLAUDE_PROJECT_DIR")
    if explicit:
        return os.path.realpath(explicit)
    cwd = payload.get("cwd") or os.getcwd()
    resolved = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
        check=False,
        capture_output=True,
        text=True,
    )
    return (
        os.path.realpath(resolved.stdout.strip())
        if resolved.returncode == 0
        else os.path.realpath(cwd)
    )


def command_cwd(payload):
    return os.path.realpath(payload.get("cwd") or os.getcwd())


def references_control_state(command, root, cwd):
    canonical = {
        os.path.realpath(os.path.join(root, relative))
        for relative in CONTROL_STATE_PATHS
    }
    suffixes = tuple(f"/{relative}" for relative in CONTROL_STATE_PATHS)
    normalized_inputs = [command, command.replace("'", "").replace('"', "")]
    tokens = shell_tokens(command)
    if tokens:
        normalized_inputs.extend(tokens)
    for text in normalized_inputs:
        for match in FILE_REFERENCE.finditer(text):
            reference = match.group(0)
            resolved = os.path.realpath(
                reference if os.path.isabs(reference) else os.path.join(cwd, reference)
            )
            if resolved in canonical or resolved.endswith(suffixes):
                return True

    # Cover commands that change directory before naming only the basename.
    state_name = re.search(
        r"(?<![A-Za-z0-9_.-])STATE\.md(?![A-Za-z0-9_.-])", command
    )
    state_directory = re.search(
        r"(?:^|[\s/'\"])(?:docs/)?orchestra(?:[\s/'\"]|$)", command
    )
    if state_name and state_directory:
        return True
    state_json_name = re.search(
        r"(?<![A-Za-z0-9_.-])state\.json(?![A-Za-z0-9_.-])", command
    )
    state_json_directory = re.search(
        r"(?<![A-Za-z0-9_.-])\.orchestra(?![A-Za-z0-9_.-])", command
    )
    if state_json_name and state_json_directory:
        return True
    return False


def shell_tokens(command):
    if "$(" in command or "`" in command or "<(" in command or ">(" in command:
        return None
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()<>")
        lexer.whitespace_split = True
        lexer.commenters = ""
        return list(lexer)
    except ValueError:
        return None


def command_segments(command):
    tokens = shell_tokens(command)
    if not tokens:
        return None
    segments = []
    current = []
    for token in tokens:
        if token in ("&&", "||", ";", "|"):
            if not current:
                return None
            segments.append(current)
            current = []
        elif token in ("&", "(", ")", "<<", "<<<", "<&", "&>"):
            return None
        else:
            current.append(token)
    if not current:
        return None
    segments.append(current)
    return segments


def strip_wrappers(words):
    index = 0
    while index < len(words) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[index]):
        index += 1
    while index < len(words) and words[index] in ("command", "env", "sudo", "exec"):
        index += 1
        if words[index - 1] == "env":
            while index < len(words) and re.fullmatch(
                r"[A-Za-z_][A-Za-z0-9_]*=.*", words[index]
            ):
                index += 1
    return words[index:]


def script_like_path(value, extensions):
    return "/" in value or value.endswith(extensions)


def shell_has_payload(args):
    value_options = {"-o", "+o", "-O", "+O", "--rcfile", "--init-file"}
    no_value_options = {
        "--login",
        "--noprofile",
        "--norc",
        "--posix",
        "--restricted",
        "--verbose",
    }
    short_no_value = set("ilrvxnefqtVXb")
    script_extensions = (
        ".sh",
        ".bash",
        ".zsh",
        ".fish",
        ".ksh",
        ".dash",
        ".csh",
        ".tcsh",
    )
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--":
            return index + 1 < len(args) and script_like_path(
                args[index + 1], script_extensions
            )
        is_short_options = arg.startswith("-") and not arg.startswith("--")
        short_flags = set(arg[1:]) if is_short_options else set()
        if arg == "-c" or (
            is_short_options
            and "c" in short_flags
            and short_flags <= short_no_value | {"c"}
        ):
            return index + 1 < len(args)
        if arg in value_options:
            index += 2
            continue
        if any(
            arg.startswith(option) and len(arg) > len(option)
            for option in ("-o", "+o", "-O", "+O")
        ) or any(arg.startswith(f"{option}=") for option in ("--rcfile", "--init-file")):
            index += 1
            continue
        if arg in no_value_options or (
            is_short_options and short_flags <= short_no_value
        ):
            index += 1
            continue
        if arg.startswith(("-", "+")):
            return False
        return script_like_path(arg, script_extensions)
    return False


def interpreter_family(program):
    for family in ("python", "node", "ruby", "irb", "perl", "php", "tclsh", "wish"):
        if program.startswith(family):
            return "tcl" if family in ("tclsh", "wish") else family
    return ""


def interpreter_has_payload(program, args):
    family = interpreter_family(program)
    inline_options = {
        "python": {"-c", "-m"},
        "node": {"-e", "--eval"},
        "ruby": {"-e"},
        "perl": {"-e"},
        "php": {"-r"},
        "irb": set(),
        "tcl": set(),
    }[family]
    value_options = {
        "python": {"-W", "-X", "--check-hash-based-pycs"},
        "node": {
            "-r",
            "--require",
            "--import",
            "--loader",
            "--conditions",
            "--inspect-port",
        },
        "ruby": {"-I", "-r", "-C", "-E", "-F", "-K"},
        "irb": {"-I", "-r"},
        "perl": {"-I", "-M", "-m", "-F"},
        "php": {"-c", "-d", "-z"},
        "tcl": {"-encoding"},
    }[family]
    no_value_options = {
        "python": {"-B", "-E", "-I", "-O", "-OO", "-q", "-s", "-S", "-u", "-v"},
        "node": {"--no-warnings", "--use-strict", "--trace-warnings"},
        "ruby": {"-d", "-v", "-w"},
        "irb": {"--simple-prompt", "--noprompt"},
        "perl": {"-w"},
        "php": {"-n", "-q"},
        "tcl": set(),
    }[family]
    script_extensions = {
        "python": (".py", ".pyw"),
        "node": (".js", ".mjs", ".cjs"),
        "ruby": (".rb",),
        "irb": (".rb",),
        "perl": (".pl", ".pm"),
        "php": (".php",),
        "tcl": (".tcl",),
    }[family]
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--":
            return index + 1 < len(args) and script_like_path(
                args[index + 1], script_extensions
            )
        if arg in inline_options:
            return index + 1 < len(args)
        if any(
            arg.startswith(option) and len(arg) > len(option)
            for option in inline_options
            if option.startswith("-") and not option.startswith("--")
        ) or any(arg.startswith(f"{option}=") for option in inline_options):
            return True
        if arg in value_options:
            index += 2
            continue
        if any(
            arg.startswith(option) and len(arg) > len(option)
            for option in value_options
            if option.startswith("-") and not option.startswith("--")
        ) or any(arg.startswith(f"{option}=") for option in value_options):
            index += 1
            continue
        if arg in no_value_options:
            index += 1
            continue
        if arg.startswith("-"):
            return False
        return script_like_path(arg, script_extensions)
    return False


def database_has_payload(program, args):
    if "<" in args:
        index = args.index("<")
        return index + 1 < len(args) and script_like_path(args[index + 1], (".sql",))

    if program.startswith("sqlite3"):
        value_options = {"-cmd", "-init", "-separator", "-newline"}
        no_value_options = {
            "-bail",
            "-batch",
            "-echo",
            "-header",
            "-noheader",
            "-readonly",
            "-safe",
        }
        positionals = []
        index = 0
        while index < len(args):
            arg = args[index]
            if arg in value_options:
                index += 2
            elif arg in no_value_options:
                index += 1
            elif arg.startswith("-"):
                return False
            else:
                positionals.append(arg)
                index += 1
        return len(positionals) >= 2

    command_options = {"-c", "--command"}
    file_options = {"-f", "--file"}
    value_options = {
        "-d",
        "--dbname",
        "-h",
        "--host",
        "-p",
        "--port",
        "-U",
        "--username",
    }
    no_value_options = {"-A", "--no-align", "-q", "--quiet", "-X", "--no-psqlrc"}
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in command_options:
            return index + 1 < len(args)
        if any(arg.startswith(f"{option}=") for option in command_options):
            return True
        if arg in file_options:
            return index + 1 < len(args) and script_like_path(args[index + 1], (".sql",))
        if any(arg.startswith(f"{option}=") for option in file_options):
            return script_like_path(arg.split("=", 1)[1], (".sql",))
        if arg in value_options:
            index += 2
            continue
        if any(arg.startswith(f"{option}=") for option in value_options):
            index += 1
            continue
        if arg in no_value_options or not arg.startswith("-"):
            index += 1
            continue
        return False
    return False


def stdin_capable_command(command):
    segments = command_segments(command)
    if not segments:
        return False
    for segment in segments:
        # Inspect every explicit shell/interpreter token, not only the first
        # program, because standard wrappers (`env -i`, `command --`, `sudo`,
        # `nohup`) can precede it and write_stdin is not hooked a second time.
        for index, token in enumerate(segment):
            program = os.path.basename(token)
            args = segment[index + 1 :]
            stdin_devices = {"-", "/dev/stdin", "/proc/self/fd/0", "/dev/fd/0"}
            if SHELL_PROGRAM.fullmatch(program):
                reads_stdin = any(
                    arg == "-s"
                    or (
                        arg.startswith("-")
                        and not arg.startswith("--")
                        and "s" in arg[1:]
                    )
                    or arg in stdin_devices
                    for arg in args
                )
                if reads_stdin or not shell_has_payload(args):
                    return True
            elif INTERPRETER_PROGRAM.fullmatch(program):
                if any(arg in stdin_devices for arg in args) or not interpreter_has_payload(
                    program, args
                ):
                    return True
            elif DATABASE_PROGRAM.fullmatch(program):
                if any(arg in stdin_devices for arg in args) or not database_has_payload(
                    program, args
                ):
                    return True
    return False


def without_safe_redirections(words):
    cleaned = []
    index = 0
    while index < len(words):
        token = words[index]
        if token in (">", ">>", ">&"):
            if index + 1 >= len(words):
                return None
            target = words[index + 1]
            if token == ">&":
                if target not in ("1", "2"):
                    return None
            elif target not in SAFE_REDIRECTS:
                return None
            if cleaned and cleaned[-1].isdigit():
                cleaned.pop()
            index += 2
            continue
        if token == "<":
            if index + 1 >= len(words):
                return None
            if cleaned and cleaned[-1].isdigit():
                cleaned.pop()
            index += 2
            continue
        if token in ("<<", "<<<", "<&", "&>"):
            return None
        cleaned.append(token)
        index += 1
    return cleaned


def safe_sed(words):
    if any(arg == "-i" or arg.startswith("-i") for arg in words[1:]):
        return False
    quiet = False
    index = 1
    while index < len(words) and words[index].startswith("-"):
        option = words[index]
        if option in ("-n", "--quiet", "--silent"):
            quiet = True
        elif option not in ("-E", "-r", "--regexp-extended"):
            return False
        index += 1
    if not quiet or index >= len(words):
        return False
    return bool(SED_PRINT_SCRIPT.fullmatch(words[index]))


def safe_find(words):
    unsafe_actions = {
        "-delete",
        "-exec",
        "-execdir",
        "-fprint",
        "-fprintf",
        "-fls",
        "-ok",
        "-okdir",
    }
    return not any(arg in unsafe_actions for arg in words[1:])


def safe_file(words):
    return not any(
        arg in ("-C", "--compile") or arg.startswith("--compile=")
        for arg in words[1:]
    )


def safe_git(words):
    index = 1
    while index < len(words) and words[index] == "-C":
        index += 2
    if index >= len(words):
        return False
    subcommand = words[index]
    args = words[index + 1 :]
    if subcommand == "worktree":
        return bool(args) and args[0] == "list"
    if subcommand not in SAFE_GIT_COMMANDS:
        return False
    return not any(
        arg in ("--ext-diff", "--textconv", "--output") or arg.startswith("--output=")
        for arg in args
    )


def safe_read_only_command(command):
    segments = command_segments(command)
    if not segments:
        return False
    for segment in segments:
        words = without_safe_redirections(segment)
        if not words or any("$" in word for word in words):
            return False
        program = os.path.basename(words[0])
        if program in SAFE_PROGRAMS:
            if program == "rg" and any(
                arg == "--pre" or arg.startswith("--pre=") for arg in words[1:]
            ):
                return False
            continue
        if program == "file" and safe_file(words):
            continue
        if program == "sed" and safe_sed(words):
            continue
        if program == "find" and safe_find(words):
            continue
        if program == "git" and safe_git(words):
            continue
        return False
    return True


def output(decision="allow", reason=None):
    result = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
        }
    }
    if reason:
        result["hookSpecificOutput"]["permissionDecisionReason"] = reason
    print(json.dumps(result))


def main():
    is_worker = bool(
        os.environ.get("ORCHESTRA_CODEX_WORKER")
        or (os.environ.get("ORCA_WORKTREE_ID") and not os.environ.get("ORCA_WORKSPACE_ID"))
    )
    if not is_worker and not os.environ.get("ORCHESTRA_CODEX_READ_ONLY"):
        output()
        return
    try:
        payload = json.load(sys.stdin)
    except (ValueError, TypeError):
        output("deny", "Codex worker guard: malformed hook input failed closed.")
        return

    tool_name = payload.get("tool_name") or payload.get("toolName") or ""
    tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
    command = tool_input.get("command") or ""
    if tool_name not in ("Bash", "apply_patch"):
        output(
            "deny",
            "Codex workers may not use inherited MCP or local tools unless the tool is explicitly proven safe.",
        )
        return
    if tool_name == "Bash" and DYNAMIC_SHELL_SYNTAX.search(command):
        output(
            "deny",
            "Codex worker Bash is literal-only: shell expansion, grouping, and "
            "descriptor-duplication syntax fails closed, including when quoted "
            "or otherwise harmless.",
        )
        return
    if references_control_state(
        command, repository_root(payload), command_cwd(payload)
    ):
        output(
            "deny",
            "Codex workers may not read or mutate coordinator-owned Orchestra state.",
        )
        return
    if BYPASS_MARKER in command:
        output("deny", "Codex workers may not create or use .claude/.bypass-guards.")
        return
    if any(reference in command for reference in LEASE_REFERENCES):
        output("deny", "Codex workers may not inspect or invoke coordinator lease controls.")
        return
    if ".orchestra/routing/" in command and re.search(
        r"\b(?:rm|rmdir|unlink|delete)\b|^\*\*\* Delete File:", command, re.MULTILINE
    ):
        output("deny", "Codex workers may not delete coordinator routing state.")
        return
    if tool_name == "apply_patch" and os.environ.get("ORCHESTRA_CODEX_READ_ONLY"):
        output("deny", "This Codex role is read-only; apply_patch is forbidden.")
        return
    if tool_name == "Bash" and (
        tool_input.get("tty") is True
        or INTERACTIVE_COMMAND.match(command)
        or SHELL_STDIN_BRIDGE.search(command)
        or stdin_capable_command(command)
    ):
        output(
            "deny",
            "Codex workers may not open interactive shell or interpreter sessions because later stdin does not rerun PreToolUse.",
        )
        return
    if tool_name == "Bash" and WORKTREE_MUTATION.search(command):
        output("deny", "Codex workers may not mutate Git worktrees; only the coordinator owns worktrees.")
        return
    if tool_name == "Bash" and os.environ.get("ORCHESTRA_CODEX_READ_ONLY"):
        if not safe_read_only_command(command):
            output(
                "deny",
                "This Codex role is read-only; Bash is limited to approved inspection commands. "
                "The generated read-only sandbox remains the primary enforcement boundary.",
            )
            return
    output()


if __name__ == "__main__":
    main()
