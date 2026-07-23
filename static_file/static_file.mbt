// ///|

///|
using @crescent {trait ServeStaticProvider, trait Responder}

///|
/// A file-system-backed provider for serving static assets. Implements the
/// `ServeStaticProvider` trait to resolve asset metadata and contents from a
/// directory on disk.
pub struct StaticFileProvider {
  /// Root directory path on disk from which files are served.
  priv path : String
}

///|
/// Creates a new `StaticFileProvider` rooted at the given directory path.
pub fn StaticFileProvider::StaticFileProvider(
  path~ : String,
) -> StaticFileProvider {
  { path, }
}

///|
fn is_safe_static_id(id : String) -> Bool {
  if id.find("\\") is Some(_) {
    return false
  }
  for segment in id.split("/") {
    if segment == ".." {
      return false
    }
  }
  true
}

///|
fn StaticFileProvider::full_path(
  self : StaticFileProvider,
  id : String,
) -> String? {
  if is_safe_static_id(id) {
    Some(self.path + "/" + id)
  } else {
    None
  }
}

/// Canonicalizes `candidate` and verifies it still resides under `root`.
/// Returns `None` if canonicalization fails (file missing) or if the resolved
/// path escapes `root` via symlink. This defends against symlinks inside the
/// static root that point to arbitrary files outside the root.

///|
async fn resolve_within_root(
  root : String,
  candidate : String,
) -> String? noraise {
  let root_path = @fs.realpath(root) catch { _ => return None }
  let candidate_path = @fs.realpath(candidate) catch { _ => return None }
  // Candidate must be equal to root, or under root with a separator.
  if candidate_path == root_path || candidate_path.has_prefix(root_path + "/") {
    Some(candidate_path)
  } else {
    None
  }
}

///|
fn static_asset_etag(
  mtime_sec : Int64,
  mtime_nsec : Int,
  size : Int64,
) -> String {
  "\"\{mtime_sec}-\{mtime_nsec}-\{size}\""
}

///|
async fn open_static_asset(path : String) -> @fs.File? noraise {
  try @fs.open(path, mode=ReadOnly) catch {
    _ => None
  } noraise {
    file =>
      if file.kind() is Regular {
        Some(file)
      } else {
        file.close()
        None
      }
  }
}

/// Resolves a static asset id to a canonical path within the provider root,
/// or `None` if the path escapes the root (via symlinks or otherwise).

///|
async fn StaticFileProvider::safe_resolve(
  self : StaticFileProvider,
  id : String,
) -> String? noraise {
  match self.full_path(id) {
    Some(candidate) => resolve_within_root(self.path, candidate)
    None => None
  }
}

///|
/// Returns metadata (ETag, modification time, path, size) for the asset
/// identified by `id`, or `None` if the file does not exist, is not a regular
/// file, or resolves outside the provider root (symlink escape).
pub impl ServeStaticProvider for StaticFileProvider with fn get_meta(
  self,
  id : String,
) -> @crescent.StaticAssetMeta? {
  match self.safe_resolve(id) {
    Some(path) =>
      match open_static_asset(path) {
        Some(file) => {
          defer file.close()
          let size = file.size() catch { _ => return None }
          let (mtime_sec, mtime_nsec) = file.mtime() catch { _ => return None }
          Some(
            @crescent.StaticAssetMeta(
              etag=static_asset_etag(mtime_sec, mtime_nsec, size),
              mtime=mtime_sec,
              path~,
              size~,
            ),
          )
        }
        None => None
      }
    None => None
  }
}

///|
/// Reads and returns the full contents of the static asset identified by `id`
/// as an HTTP response, including `Content-Length` and `ETag` headers.
/// Returns 404 if the asset is missing or resolves outside the provider root.
pub impl ServeStaticProvider for StaticFileProvider with fn get_contents(
  self,
  id : String,
) -> &Responder {
  match self.safe_resolve(id) {
    Some(path) =>
      match open_static_asset(path) {
        Some(file) => {
          defer file.close()
          let headers = try {
            let size = file.size()
            let (mtime_sec, mtime_nsec) = file.mtime()
            let headers : Map[String, String] = Map([])
            headers.set("Content-Length", size.to_string())
            headers.set("ETag", static_asset_etag(mtime_sec, mtime_nsec, size))
            headers
          } catch {
            _ => {}
          }
          try file.read_all().binary() catch {
            _ => @crescent.HttpResponse(status_code=NotFound).body("Not Found")
          } noraise {
            contents =>
              @crescent.HttpResponse(status_code=OK, headers~).body(contents)
          }
        }
        None => @crescent.HttpResponse(status_code=NotFound).body("Not Found")
      }
    None => @crescent.HttpResponse(status_code=NotFound).body("Not Found")
  }
}

///|
fn mime_type_for_extension(ext : String) -> String? {
  // Text
  if ext == "html" || ext == "htm" {
    return Some("text/html; charset=utf-8")
  }
  if ext == "css" {
    return Some("text/css; charset=utf-8")
  }
  if ext == "js" || ext == "mjs" {
    return Some("application/javascript; charset=utf-8")
  }
  if ext == "json" {
    return Some("application/json; charset=utf-8")
  }
  if ext == "xml" {
    return Some("application/xml; charset=utf-8")
  }
  if ext == "txt" {
    return Some("text/plain; charset=utf-8")
  }
  if ext == "csv" {
    return Some("text/csv; charset=utf-8")
  }
  if ext == "md" {
    return Some("text/markdown; charset=utf-8")
  }
  // Images
  if ext == "png" {
    return Some("image/png")
  }
  if ext == "jpg" || ext == "jpeg" {
    return Some("image/jpeg")
  }
  if ext == "gif" {
    return Some("image/gif")
  }
  if ext == "svg" {
    return Some("image/svg+xml")
  }
  if ext == "ico" {
    return Some("image/x-icon")
  }
  if ext == "webp" {
    return Some("image/webp")
  }
  if ext == "avif" {
    return Some("image/avif")
  }
  // Fonts
  if ext == "woff" {
    return Some("font/woff")
  }
  if ext == "woff2" {
    return Some("font/woff2")
  }
  if ext == "ttf" {
    return Some("font/ttf")
  }
  if ext == "otf" {
    return Some("font/otf")
  }
  // Media
  if ext == "mp4" {
    return Some("video/mp4")
  }
  if ext == "webm" {
    return Some("video/webm")
  }
  if ext == "mp3" {
    return Some("audio/mpeg")
  }
  if ext == "ogg" {
    return Some("audio/ogg")
  }
  // Application
  if ext == "wasm" {
    return Some("application/wasm")
  }
  if ext == "pdf" {
    return Some("application/pdf")
  }
  if ext == "zip" {
    return Some("application/zip")
  }
  if ext == "gz" {
    return Some("application/gzip")
  }
  if ext == "xhtml" {
    return Some("application/xhtml+xml; charset=utf-8")
  }
  None
}

///|
/// Returns the MIME type for the given file extension.
pub impl ServeStaticProvider for StaticFileProvider with fn get_type(
  _,
  ext : String,
) -> String? {
  mime_type_for_extension(ext)
}

///|
/// Returns the content-encoding mappings (e.g. file extension to encoding name).
/// This implementation returns an empty map, indicating no pre-encoded variants.
pub impl ServeStaticProvider for StaticFileProvider with fn get_encodings(_) -> Map[
  String,
  String,
] {
  {}
}

///|
/// Returns the list of filenames to try when resolving a directory request to an
/// index document (e.g. `"index.html"`, `"index.htm"`).
pub impl ServeStaticProvider for StaticFileProvider with fn get_index_names(_) -> Array[
  String,
] {
  [
    "index.html", "index.htm", "index.txt", "index.md", "index.json", "index.xml",
    "index.xhtml", "default.html", "default.htm", "home.html", "home.htm",
  ]
}

///|
/// Returns whether unmatched requests should fall through to subsequent
/// middleware. This implementation returns `false`, meaning a 404 is returned
/// for missing assets.
pub impl ServeStaticProvider for StaticFileProvider with fn get_fallthrough(_) -> Bool {
  false
}
