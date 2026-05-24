import Link from "next/link";
import ReactMarkdown, { type Components } from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeHighlight from "rehype-highlight";

/**
 * Markdown renderer for TLK engineering docs.
 *
 * Styled to match Studio chrome — Newsreader display for headings,
 * Inter for body, JetBrains Mono for code. GFM enabled for the tables
 * the specs lean on (TLK-001 component matrix, TLK-019 inventory).
 *
 * Anchored headings — every h2/h3 gets a stable id derived from its
 * text so reviewers can deep-link sections. Slug logic intentionally
 * conservative; collisions across a single doc are rare in practice.
 */
export function EngMarkdown({
  body,
  fromSlug,
  compact = false,
}: {
  body: string;
  /** Source doc slug — when set, path-like inline `code` becomes a
   *  link to /eng/file/... carrying a `?from=/eng/<slug>` back ref. */
  fromSlug?: string;
  /** Tightens vertical rhythm — for use inside the header data sheet
   *  where the grid row already supplies padding. */
  compact?: boolean;
}) {
  return (
    <article className={`eng-doc ${compact ? "eng-doc--compact" : ""}`}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        rehypePlugins={[[rehypeHighlight, { detect: true, ignoreMissing: true }]]}
        components={buildComponents(fromSlug)}
      >
        {body}
      </ReactMarkdown>
    </article>
  );
}

const VIEWABLE_EXT_RE =
  /\.(swift|ts|tsx|js|jsx|mjs|cjs|md|mdx|json|css|scss|html?|sh|bash|zsh|ya?ml|toml|txt)(?::\d+(?:-\d+)?)?$/i;

function isViewablePath(text: string): { path: string } | null {
  if (!text) return null;
  if (text.includes("://")) return null;
  if (text.startsWith("http") || text.startsWith("//")) return null;
  // Must look like a path — contains a slash anywhere.
  if (!text.includes("/")) return null;
  if (!VIEWABLE_EXT_RE.test(text)) return null;
  // Strip an optional trailing `:line` or `:start-end` so we can resolve
  // the underlying file. Line targeting is left as future work.
  const cleaned = text.replace(/:\d+(?:-\d+)?$/, "");
  return { path: cleaned };
}

function buildFileHref(p: string, fromSlug?: string): string {
  const segments = p.split("/").map((s) => encodeURIComponent(s));
  const from = fromSlug ? `?from=${encodeURIComponent(`/eng/${fromSlug}`)}` : "";
  return `/eng/file/${segments.join("/")}${from}`;
}

function buildComponents(fromSlug: string | undefined): Components {
  return {
  h2: ({ children }) => (
    <h2
      id={slugify(children)}
      className="font-display text-[20px] font-medium tracking-tight text-studio-ink mt-10 mb-3 pb-1.5 border-b border-studio-edge scroll-mt-24"
    >
      {children}
    </h2>
  ),
  h3: ({ children }) => (
    <h3
      id={slugify(children)}
      className="font-display text-[16px] font-medium tracking-tight text-studio-ink mt-7 mb-2 scroll-mt-24"
    >
      {children}
    </h3>
  ),
  h4: ({ children }) => (
    <h4 className="font-mono text-[10px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint mt-5 mb-1.5">
      {children}
    </h4>
  ),
  p: ({ children }) => (
    <p className="font-sans text-[14px] leading-[1.65] text-studio-ink/90 my-3">
      {children}
    </p>
  ),
  a: ({ href, children }) => (
    <a
      href={href}
      className="text-studio-ink underline decoration-studio-edge underline-offset-2 hover:decoration-studio-ink"
      target={href?.startsWith("http") ? "_blank" : undefined}
      rel={href?.startsWith("http") ? "noopener noreferrer" : undefined}
    >
      {children}
    </a>
  ),
  ul: ({ children }) => (
    <ul className="font-sans text-[14px] leading-[1.65] text-studio-ink/90 my-3 ml-5 list-disc space-y-1">
      {children}
    </ul>
  ),
  ol: ({ children }) => (
    <ol className="font-sans text-[14px] leading-[1.65] text-studio-ink/90 my-3 ml-5 list-decimal space-y-1">
      {children}
    </ol>
  ),
  li: ({ children }) => <li className="pl-1">{children}</li>,
  strong: ({ children }) => (
    <strong className="font-semibold text-studio-ink">{children}</strong>
  ),
  em: ({ children }) => <em className="italic">{children}</em>,
  hr: () => <hr className="my-8 border-studio-edge" />,
  blockquote: ({ children }) => (
    <blockquote className="border-l-2 border-studio-edge pl-4 my-4 font-sans text-[14px] italic text-studio-ink-faint">
      {children}
    </blockquote>
  ),
  code: ({ className, children, node: _node, ...rest }) => {
    // Inline code has no language class; block code has `language-foo`.
    const isInline = !className;
    if (isInline) {
      const text = extractText(children);
      const viewable = isViewablePath(text);
      if (viewable) {
        return (
          <Link
            href={buildFileHref(viewable.path, fromSlug)}
            className="font-mono text-[12.5px] bg-studio-canvas-alt text-studio-ink/90 px-1 py-px rounded-[2px] underline decoration-studio-edge underline-offset-2 hover:decoration-studio-ink hover:text-studio-ink transition-colors"
          >
            {children}
          </Link>
        );
      }
      return (
        <code
          className="font-mono text-[12.5px] bg-studio-canvas-alt text-studio-ink/90 px-1 py-px rounded-[2px]"
          {...rest}
        >
          {children}
        </code>
      );
    }
    return (
      <code className={`${className ?? ""} font-mono text-[12.5px]`} {...rest}>
        {children}
      </code>
    );
  },
  pre: ({ children }) => (
    <pre className="my-4 overflow-x-auto rounded-md border border-studio-edge bg-studio-canvas-alt/40 p-4 font-mono text-[12.5px] leading-[1.55]">
      {children}
    </pre>
  ),
  table: ({ children }) => (
    <div className="my-5 overflow-x-auto">
      <table className="w-full border-collapse font-sans text-[13px]">
        {children}
      </table>
    </div>
  ),
  thead: ({ children }) => (
    <thead className="border-b border-studio-edge text-left">{children}</thead>
  ),
  th: ({ children }) => (
    <th className="px-3 py-1.5 font-mono text-[10px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
      {children}
    </th>
  ),
  td: ({ children }) => (
    <td className="px-3 py-1.5 border-b border-studio-edge/60 align-top text-studio-ink/85">
      {children}
    </td>
  ),
  };
}

function slugify(node: React.ReactNode): string {
  const text = extractText(node);
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

function extractText(node: React.ReactNode): string {
  if (typeof node === "string") return node;
  if (typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(extractText).join("");
  if (node && typeof node === "object" && "props" in node) {
    // @ts-expect-error — children is dynamic
    return extractText(node.props.children);
  }
  return "";
}
