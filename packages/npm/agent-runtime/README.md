# @talkie/agent-runtime

Talkie-facing wrapper for background agent session adapters.

The package is the public runtime contract used by TalkieAgent's Node dispatcher.
It currently delegates to `@openscout/agent-sessions`, but Talkie code should
prefer this package name so the implementation can move without changing the app
bundle or settings surface.

```sh
npm install --prefix "$HOME/.talkie/agent-runtime" @talkie/agent-runtime
$HOME/.talkie/agent-runtime/bin/talkie-agent-runtime doctor
```
