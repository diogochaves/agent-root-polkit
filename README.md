# agent-root-polkit

Omarchy's polkit dialog, plus one line saying which coding agent is asking for
root and why, read from [agent-root](https://github.com/jankeesvw/agent-root):

```
        Claude: "Install Valkey (Redis) for Sidekiq"
             omarchy · session 622d8aad
  Authorize running '/usr/bin/pacman -S --noconfirm valkey'
             [ Enter password ]
```

A clone of `omarchy.polkit` from Omarchy 4.0.4 (`chaves.polkit`, with
`clonedFrom`, so it keeps the trusted authentication capability). For any
request that isn't pkexec's, or a pkexec with no agent above it, the dialog is
the stock one. The first commit is Omarchy's plugin as it ships, so
`git diff HEAD~1` shows everything this adds.

## How it knows

When a request for `org.freedesktop.policykit.exec` starts, the dialog runs
`requester` with polkit's message. It finds the pending `pkexec` whose command
line matches, and from its parent and the processes above it reads:

- the reason, when the parent is agent-root: its first argument, or
  `AGENT_ROOT_REASON` for yay and paru
- the agent, by program name (`claude`, `codex`, `opencode`, `cursor-agent`, …)
  or `AI_AGENT`
- the project, from the agent's folder (its git repository's name)
- the herdr workspace (`HERDR_WORKSPACE_ID`, named by `herdr workspace get`) and
  Claude Code's session id

Two pending requests with the same command line can't be told apart, so then
the line is left out rather than guessed.

All of this comes from processes that run as you, so an agent can fake any of
it. It is context, not proof: the command polkit shows is the part to read.

## Why it matches on the message

Matching the message against `/proc` is the workaround. These were the other
ways to get the reason into the dialog, checked against polkit 127 and
Quickshell 0.3.1:

- **polkit's own details.** polkitd passes the agent `polkit.subject-pid`,
  and for pkexec the subject is its parent, agent-root itself, so the dialog
  would know exactly who asks with no matching at all. Quickshell's polkit
  listener drops the details (`listener.hpp`: "Details intentionally omitted
  because nothing seems to use them"), so a QML dialog only gets the action id,
  message, icon and cookie. This is the right fix, and it needs Quickshell to
  expose them, then Omarchy's plugin to pass them on.
- **The reason in the message.** pkexec writes the message itself ("needed to
  run `$(cmdline_short)'"). A `.policy` file with
  `org.freedesktop.policykit.exec.path` can replace it, but only with a fixed
  text per program, installed as root, and its `$(…)` fields are only the
  details pkexec sets. There's no way to pass a reason per call.
- **The reason in the command line**, say `pkexec env REASON=… pacman …`. It
  would show in any dialog, even the stock one, but pkexec cuts a command line
  over 80 characters to its start and end, so the reason would push the
  command out of sight. Not a good trade in the one place you need to read it.
- **Details of our own, through `pkcheck --details`.** polkitd only accepts
  details from trusted callers ("Only trusted callers (e.g. uid 0 or an action
  owner) can use CheckAuthorization() and pass details"), and `pkcheck` only
  checks, so something running as root would still have to run the command.
  Quickshell would drop the details anyway.
- **A side channel**, agent-root writing the reason to a file under
  `$XDG_RUNTIME_DIR`. The dialog would still have to work out which request
  the file belongs to, the same matching as now, and agent-root would need a
  change for it. Reading agent-root's arguments needs nothing from it.

## Install

```bash
git clone https://github.com/diogochaves/agent-root-polkit ~/.local/share/agent-root-polkit
ln -s ~/.local/share/agent-root-polkit ~/.config/omarchy/plugins/chaves.polkit
omarchy-shell shell rescanPlugins
omarchy plugin enable chaves.polkit
omarchy restart shell
```

`requester` needs `jq`. Enabling the plugin disables `omarchy.polkit`, and the
restart is needed: switched live, the clone tries to register while the
built-in still holds the session, polkit refuses it, and then the built-in
goes, leaving no agent at all (pkexec then asks in the terminal).

Try it with `agent-root "Try the agent line" whoami`.

With the reason in the dialog, agent-root's own notification says the same
thing twice.

## Undo

```bash
omarchy plugin disable chaves.polkit
rm ~/.config/omarchy/plugins/chaves.polkit
omarchy restart shell
```

Disabling the clone brings `omarchy.polkit` back, after the same restart.

## Tests

```bash
test/requester_test.sh
```

Runs `requester` against a stand-in pkexec that only waits and a notify-send
that does nothing, so no dialog or notification appears.

## Keeping up with Omarchy

The dialog is a copy: Omarchy's later changes to `omarchy.polkit` don't reach
it. The changes here are the `requester*` properties and functions, the
`requesterProc` Process and the `requesterPill` above `justificationPill` in
`PolkitAgent.qml`.
