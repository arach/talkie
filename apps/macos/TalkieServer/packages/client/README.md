# @talkie/client

Typed Talkie client for code-mode agents and integrations.

The client is the supported TypeScript surface for Talkie data access. Agents
should code against this package instead of inspecting Talkie's database,
inventing generated shell helpers, or walking private storage layouts.

```ts
import { createTalkieClient } from "@talkie/client";

const talkie = createTalkieClient();

const captures = await talkie.captures.search({
  query: "console agent settings",
  kinds: ["screenshot", "video"],
  since: "7d",
  limit: 10,
});
```

Protocol types and schemas are available from the package subpath:

```ts
import type { CaptureSearchQuery } from "@talkie/client/protocol";
import { captureSearchQuerySchema } from "@talkie/client/protocol";
```

The default client uses Talkie's bridge transport when available. The transport
is replaceable so tests, embedded runtimes, MCP adapters, and future in-process
hosts can reuse the same typed interface.
