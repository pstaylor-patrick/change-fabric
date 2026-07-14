---
name: pst:nextjs
description: Next.js App Router rubric, composed from Vercel's best-practices guidance plus our server-first defaults. Auto-applied by the pst shim on every Next.js change; also invocable directly.
auto:
  extensions: [ts, tsx, js, jsx]
  require:
    - dep: [next]
---

# Next.js Cheat Sheet

Source: the vercel-labs/next-skills `best-practices` skill (that repo has since moved to
https://github.com/vercel/next.js/tree/canary/skills, which ships workflow skills only; the
best-practices content now lives in Next.js's bundled docs and the auto-generated
AGENTS.md/CLAUDE.md from `next dev` on 16.3+) + Next.js App Router docs

Question: Does this route render on the server by default and mutate through a Server Action?

## Vendor base (Vercel best practices)

Favor:
- Node.js runtime by default; edge only if the project already runs it or a specific requirement demands it
- `params`/`searchParams` typed as `Promise<...>` and awaited (Next.js 15+); `use()` only in synchronous components
- `metadata` / `generateMetadata` in Server Components only, never a file with `'use client'`
- `React.cache()` to dedupe a fetch shared by `generateMetadata` and the page
- `'use cache'` with `cacheLife()` for cacheable reads, but only once the experimental directive is enabled (`experimental.useCache` or `experimental.dynamicIO` in `next.config`); it is not on by default
- `next/script` with `strategy="afterInteractive"` for third-party scripts that would otherwise cause hydration mismatches

Avoid:
- edge runtime picked with no measured reason
- synchronous access to `params`/`searchParams` without `await` or `use()`
- metadata exports inside a `'use client'` file
- browser-only APIs, non-deterministic values, or invalid HTML nesting during server render

## Our layer on top

Favor:
- Server Components by default; add `'use client'` only at the smallest leaf that truly needs interactivity
- Server Actions for every write and form submission, including from inside a Client Component boundary
- Suspense boundaries around slow segments, with explicit `loading`/`error`/`not-found` files

Avoid:
- `'use client'` as a default wrapper on a page or layout
- a client-side `fetch`/`axios` mutation where a Server Action would do
- an `app/api` route handler standing in for a form submission a Server Action already covers

Exception: client-side mutation is fine when the feature needs client-only interaction that a
Server Action round-trip cannot give (drag state, optimistic UI mid-keystroke). Keep the
`'use client'` boundary as small as possible even then, and still call a Server Action for
the actual write.

CI (mechanically enforced):
- `next build` passes
- lint max warnings = 0
- `tsc --noEmit` passes; this catches unawaited `params`/`searchParams` once they are typed as `Promise<...>`

Review-time (no tool checks these, a human judges them in code review):
- Server Actions preferred over client-side `fetch`/`axios` mutations
- `'use client'` boundaries kept minimal
- every exception carries a stated reason

Agent protocol:
1. Default new routes/pages/layouts to Server Components.
2. Route every write through a Server Action; note the reason for any exception.
3. Await `params`/`searchParams`; never access them synchronously.
4. Keep `'use client'` boundaries minimal and push state down.
5. Preserve visible behavior.
