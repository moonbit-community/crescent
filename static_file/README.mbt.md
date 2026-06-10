# Static File

A file-system-backed static-asset provider for Crescent.

Mount a directory under a URL prefix and the framework will serve every
file inside it: correct `Content-Type`, stable `ETag`, directory index
resolution, and `If-None-Match` / `If-Modified-Since` short-circuits — all
without writing a handler. The provider plugs into Crescent through the
`@crescent.ServeStaticProvider` trait, which is also the extension point
for non-filesystem sources (embedded assets, S3, in-memory caches).

## Quick Start

```moonbit nocheck
///|
async fn main {
  let app = @crescent.App()
  app.static_assets("/assets", @static_file.StaticFileProvider(path="./public"))
  app.serve(port=4000)
}
```

With a `./public/` directory containing:

```
./public/
├── index.html
├── main.css
└── logo.png
```

the app will respond to:

| Request | Behaviour |
| ------- | --------- |
| `GET /assets/main.css` | `200 OK` + `Content-Type: text/css; charset=utf-8` + ETag |
| `GET /assets` or `GET /assets/` | Serves `./public/index.html` (directory index) |
| `GET /assets/missing.txt` | `404 Not Found` |
| `GET /assets/../secret.txt` | `404 Not Found` (traversal blocked) |
| `HEAD /assets/main.css` | headers only, same ETag |
| `GET /assets/main.css` with matching `If-None-Match` | `304 Not Modified`, empty body |

## Install

This package is included with `bobzhang/crescent`. Import it directly:

```
import {
  "bobzhang/crescent/static_file"
  ...
}
```

## What It Does For You

- **MIME type detection.** Maps common file extensions to the right
  `Content-Type`, with `; charset=utf-8` added to text formats. See the
  table below.
- **ETag generation.** Each asset gets a strong ETag derived from its
  modification time and size (`"mtime_sec-mtime_nsec-size"`). Clients can
  use it with `If-None-Match` to skip re-downloading unchanged files.
- **Last-Modified.** Served automatically alongside the ETag for clients
  that prefer `If-Modified-Since`.
- **Directory indexes.** A request for a directory falls through to the
  first matching index file (`index.html`, `index.htm`, `index.md`, and
  several more — see the full list below).
- **Traversal protection.** Any path containing a `..` segment or a
  backslash is refused before the filesystem is touched.
- **Symlink escape protection.** After resolving the request to a
  candidate path, the provider canonicalizes it with `realpath` and
  verifies the result still lives under the root. A symlink inside the
  root that points outside will return `404`, not the target file.
- **Grouped mounts.** `static_assets` works inside `app.group("/prefix",
  ...)` so you can nest static mounts under a parent scope.

## MIME Type Detection

The provider maps extensions to content types via `get_type`. Every text
format gets a `; charset=utf-8` suffix so browsers render non-ASCII
content correctly.

```mbt check
///|
test "get_type returns common MIME types" {
  let provider = @static_file.StaticFileProvider(path=".")
  // text
  assert_eq(provider.get_type("html"), Some("text/html; charset=utf-8"))
  assert_eq(provider.get_type("css"), Some("text/css; charset=utf-8"))
  assert_eq(
    provider.get_type("js"),
    Some("application/javascript; charset=utf-8"),
  )
  assert_eq(provider.get_type("json"), Some("application/json; charset=utf-8"))
  // images
  assert_eq(provider.get_type("png"), Some("image/png"))
  assert_eq(provider.get_type("jpg"), Some("image/jpeg"))
  assert_eq(provider.get_type("svg"), Some("image/svg+xml"))
  // fonts
  assert_eq(provider.get_type("woff2"), Some("font/woff2"))
  // application
  assert_eq(provider.get_type("wasm"), Some("application/wasm"))
  assert_eq(provider.get_type("pdf"), Some("application/pdf"))
}
```

Unknown extensions return `None`; the framework falls back to
`application/octet-stream` so untyped binaries still download
successfully rather than 500'ing:

```mbt check
///|
test "get_type returns None for unknown extensions" {
  let provider = @static_file.StaticFileProvider(path=".")
  assert_eq(provider.get_type("xyz"), None)
  assert_eq(provider.get_type(""), None)
}
```

### Supported extensions

| Category | Extensions |
| -------- | ---------- |
| Text | `html`, `htm`, `css`, `js`, `mjs`, `json`, `xml`, `txt`, `csv`, `md` |
| Images | `png`, `jpg`, `jpeg`, `gif`, `svg`, `ico`, `webp`, `avif` |
| Fonts | `woff`, `woff2`, `ttf`, `otf` |
| Media | `mp4`, `webm`, `mp3`, `ogg` |
| Application | `wasm`, `pdf`, `zip`, `gz`, `xhtml` |

If you need a type this list doesn't cover, implement
`@crescent.ServeStaticProvider` yourself and delegate to
`StaticFileProvider` for the extensions it handles — the trait is
deliberately open so you can compose providers.

## Directory Index Resolution

A request for `/assets` or `/assets/` is resolved by trying each name in
`get_index_names` in order and serving the first one that exists. The
default list is tuned for the conventional project layouts:

```mbt check
///|
test "directory index names default list" {
  let provider = @static_file.StaticFileProvider(path=".")
  let names = provider.get_index_names()
  // `index.html` is tried first — by convention the canonical entry point
  assert_eq(names[0], "index.html")
  // markdown and JSON fallbacks for content-heavy sites
  assert_true(names.contains("index.md"))
  assert_true(names.contains("index.json"))
  // `default.html` / `home.html` for legacy layouts
  assert_true(names.contains("default.html"))
  assert_true(names.contains("home.html"))
}
```

Full default list: `index.html`, `index.htm`, `index.txt`, `index.md`,
`index.json`, `index.xml`, `index.xhtml`, `default.html`, `default.htm`,
`home.html`, `home.htm`.

## Asset Metadata and ETags

`get_meta` opens the file, stats it, and returns a `StaticAssetMeta`
populated with the canonical path, size, ETag, and mtime. The ETag is a
strong validator built from `"<mtime_sec>-<mtime_nsec>-<size>"`, which
changes whenever the file is rewritten or touched:

```mbt check
///|
async test "get_meta returns size, path, and etag for a real file" {
  let provider = @static_file.StaticFileProvider(path="static_file/testdata")
  guard provider.get_meta("hello.txt") is Some(meta) else {
    fail("expected metadata for hello.txt")
  }
  assert_eq(meta.size, Some(16L))
  assert_true(meta.etag is Some(_))
  // path is canonicalized (absolute), so check the suffix
  guard meta.path is Some(p) else { fail("expected meta.path") }
  assert_true(p.has_suffix("static_file/testdata/hello.txt"))
}
```

Missing files — or files that resolve outside the root via a symlink —
return `None`, which the framework translates into a `404`:

```mbt check
///|
async test "get_meta returns None for missing files" {
  let provider = @static_file.StaticFileProvider(path="static_file/testdata")
  assert_true(provider.get_meta("does_not_exist.txt") is None)
}
```

## Conditional Requests

When the framework serves an asset with an ETag, it also handles the
incoming conditional headers automatically:

- **`If-None-Match: <etag>`** — responds `304 Not Modified` with an empty
  body if the current ETag matches. Weak validators (`W/"..."`) and
  comma-separated multi-entry lists (`"foo", "bar"`) are honoured.
- **`If-Modified-Since: <http-date>`** — responds `304` if the file's
  mtime is not newer than the client's cached copy.
- **Precedence** — if both headers are present, `If-None-Match` wins (per
  RFC 9110 §13.1.3).

Bytes are only transferred when the client's cache copy is genuinely stale.
This cuts bandwidth dramatically for long-lived static assets like CSS,
fonts, and JavaScript bundles.

## Security: Traversal and Symlink Escape

Two independent defences guard the root directory.

**Path traversal.** Any request path that decodes into a segment equal to
`".."` is rejected before the filesystem is touched. The check is
per-segment, so a filename like `file..ext` is fine — only the special
parent-directory segment is blocked. Backslashes are also refused, to stop
Windows-style separators from side-stepping the segment check.

**Symlink escape.** Even if the request path looks benign, a symlink *inside*
the root could still point to `/etc/passwd` or any other file on disk. The
provider defeats this by calling `realpath` on both the root and the
candidate, then checking that the canonicalized candidate is either equal
to the root or starts with `root + "/"`. A symlink pointing outside the
root trips this check and the request returns `404` with no body.

The test suite includes a regression test that creates a real symlink into
`/etc/passwd` and asserts the provider refuses to serve it. Port it to a
new deployment if you want a paranoia-grade smoke test.

## Fallthrough Behaviour

`get_fallthrough` returns `false`, so requests that don't match an asset
respond with `404 Not Found` *from this provider* instead of falling
through to later routes or middleware. That's usually what you want —
a missing `/assets/foo.png` should not accidentally invoke a React
single-page-app handler mounted at `/*`:

```mbt check
///|
test "fallthrough is disabled by default" {
  let provider = @static_file.StaticFileProvider(path=".")
  assert_eq(provider.get_fallthrough(), false)
}
```

If you need the opposite — e.g. to serve `/docs/**` from disk, but fall
back to a templated 404 from an outer handler — write a wrapper that
implements `ServeStaticProvider` and delegates every method except
`get_fallthrough` to `StaticFileProvider`:

```moonbit nocheck
///|
pub struct FallthroughProvider {
  inner : @static_file.StaticFileProvider
}

///|
pub impl @crescent.ServeStaticProvider for FallthroughProvider with fn get_fallthrough(
  _,
) -> Bool {
  true
}

// delegate the remaining methods to `self.inner`...
```

## Pre-Encoded Variants

`get_encodings` returns an empty map, meaning this provider does **not**
serve pre-compressed variants like `main.css.gz` or `main.css.br`. If you
pre-compress your assets at build time and want the framework to pick the
right encoding based on the request's `Accept-Encoding`, write a custom
provider whose `get_encodings` returns a map like:

```moonbit nocheck
///|
fn _example_encodings() -> Map[String, String] {
  { "gzip": ".gz", "br": ".br" }
}
```

The framework will check for `main.css.gz` / `main.css.br` before falling
back to the plain file.
