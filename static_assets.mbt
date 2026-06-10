// App::static_assets mount + middleware: prefix matching, asset-id
// extraction, content negotiation across encodings/index files, and
// the StaticResolvedResponder that merges asset headers onto the
// response without clobbering middleware-set values.

///|
fn normalize_mount_path(path : String) -> String {
  if path == "" {
    "/"
  } else if path.length() > 1 && path[path.length() - 1:] == "/" {
    path[:path.length() - 1].to_owned()
  } else {
    path
  }
}

///|
test "normalize_mount_path normalizes empty, root, and trailing slashes" {
  inspect(normalize_mount_path(""), content="/")
  inspect(normalize_mount_path("/"), content="/")
  inspect(normalize_mount_path("/api/"), content="/api")
  inspect(normalize_mount_path("/api"), content="/api")
}

///|
fn mounted_asset_id(mount_path : String, request_path : String) -> String {
  if mount_path == "/" {
    if request_path == "/" {
      ""
    } else {
      request_path[1:].to_owned()
    }
  } else if request_path.length() == mount_path.length() {
    ""
  } else {
    request_path[mount_path.length() + 1:].to_owned()
  }
}

///|
test "mounted_asset_id extracts asset id relative to mount path" {
  inspect(mounted_asset_id("/", "/"), content="")
  inspect(mounted_asset_id("/", "/hello.txt"), content="hello.txt")
  inspect(mounted_asset_id("/static", "/static"), content="")
  inspect(mounted_asset_id("/static", "/static/hello.txt"), content="hello.txt")
  inspect(
    mounted_asset_id("/static", "/static/sub/file.txt"),
    content="sub/file.txt",
  )
}

///|
struct StaticResolvedResponder {
  inner : &Responder
  asset_headers : Map[String, String]
}

///|
pub impl Responder for StaticResolvedResponder with fn options(self, res) -> Unit {
  self.inner.options(res)
  if res.status_code == OK {
    self.asset_headers.each((key, value) => {
      if !@httputil.has_header_case_insensitive(res.headers, key) {
        res.headers.set(key, value)
      }
    })
  }
}

///|
pub impl Responder for StaticResolvedResponder with fn output(self, buf) -> Unit {
  self.inner.output(buf)
}

///|
pub impl Responder for StaticResolvedResponder with fn output_bytes(self) -> Bytes? {
  self.inner.output_bytes()
}

///|
/// Mounts a static asset provider at the given path, serving files with ETag/Last-Modified caching and content negotiation.
pub fn App::static_assets(
  self : App,
  path : String,
  provider : &ServeStaticProvider,
) -> Unit {
  let mount_path = normalize_mount_path(self.base_path + path)
  self.use_middleware(
    (event, next) => {
      let request_path = event.req.path()
      if !@httputil.path_scope_matches(mount_path, request_path) {
        return next()
      }

      // Method check
      if event.req.http_method != Get && event.req.http_method != Head {
        if provider.get_fallthrough() {
          return next()
        }
        event.res.headers.set("Allow", "GET, HEAD")
        return HttpResponse(status_code=MethodNotAllowed)
      }
      let original_id = mounted_asset_id(mount_path, request_path)
      let if_none_match = event.req.get_header("if-none-match")
      let if_modified_since = event.req.get_header("if-modified-since")

      // Parse Accept-Encoding
      // Headers are Map[StringView, StringView]
      let accept_encoding = event.req
        .get_header("accept-encoding")
        .unwrap_or("")
      let encodings = provider.get_encodings()
      let matched_encodings = []
      if !encodings.is_empty() {
        // Token-safe Vary append: don't clobber existing Vary values
        // (e.g. "Origin" from CORS middleware).
        @httputil.append_token_case_insensitive(
          event.res.headers,
          "Vary",
          "Accept-Encoding",
        )
      }
      if accept_encoding != "" {
        // split requires `chars` label
        for pair in accept_encoding.split(",") {
          match parse_accept_encoding_token(pair) {
            Some(encoding) =>
              match encodings.get(encoding) {
                Some(mapped) => matched_encodings.push(mapped)
                None => ()
              }
            None => () // q=0 — client refuses this encoding
          }
        }
      }

      // Search paths
      let mut id = original_id
      let mut meta : StaticAssetMeta? = None
      let index_names = provider.get_index_names()
      if index_names.length() == 0 {
        ignore(index_names.push("/index.html"))
      }

      // Search logic: suffix -> encoding
      let mut found = false
      let suffixes = [""]
      suffixes.append(index_names)
      let try_encodings = matched_encodings.copy()
      try_encodings.push("") // Add empty encoding (identity)
      for suffix in suffixes {
        if found {
          break
        }
        for encoding in try_encodings {
          let try_id = id + suffix + encoding
          match provider.get_meta(try_id) {
            Some(m) => {
              meta = Some(m)
              id = try_id
              found = true
              break
            }
            None => ()
          }
        }
      }
      match meta {
        None => {
          if provider.get_fallthrough() {
            return next()
          }
          return HttpResponse(status_code=NotFound).body("Not Found")
        }
        Some(meta) => {
          let meta = match meta.etag {
            Some(etag) =>
              if if_none_match.map(header => if_none_match_matches(header, etag)) ==
                Some(true) {
                match provider.get_meta(id) {
                  Some(revalidated_meta) =>
                    match revalidated_meta.etag {
                      Some(revalidated_etag) if revalidated_etag == etag =>
                        return HttpResponse(
                          status_code=NotModified,
                          headers=static_not_modified_headers(
                            event.res.headers,
                            revalidated_meta,
                          ),
                        )
                      _ => revalidated_meta
                    }
                  None => meta
                }
              } else {
                meta
              }
            None => meta
          }
          let meta = match (if_none_match, if_modified_since, meta.mtime) {
            (None, Some(header), Some(mtime)) if if_modified_since_matches(
                header, mtime,
              ) =>
              match provider.get_meta(id) {
                Some(revalidated_meta) =>
                  match revalidated_meta.mtime {
                    Some(revalidated_mtime) if if_modified_since_matches(
                        header, revalidated_mtime,
                      ) =>
                      return HttpResponse(
                        status_code=NotModified,
                        headers=static_not_modified_headers(
                          event.res.headers,
                          revalidated_meta,
                        ),
                      )
                    _ => revalidated_meta
                  }
                None => meta
              }
            _ => meta
          }
          let asset_headers = static_asset_headers(provider, id, meta)
          if event.req.http_method == Head {
            let head_headers = @httputil.copy_headers(event.res.headers)
            asset_headers.each((key, value) => {
              if !@httputil.has_header_case_insensitive(head_headers, key) {
                head_headers.set(key, value)
              }
            })
            return HttpResponse(status_code=OK, headers=head_headers)
          }
          let contents = provider.get_contents(id)
          StaticResolvedResponder::{ inner: contents, asset_headers }
        }
      }
    },
    base_path=mount_path,
  )
}
