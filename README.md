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

Matching on the message is the workaround. polkit already tells the agent which
process asked (`polkit.subject-pid`, which for pkexec is agent-root itself),
but Quickshell's polkit API leaves those details out, so the dialog never sees
them.

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
