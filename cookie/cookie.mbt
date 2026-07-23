///|
/// The SameSite attribute for cookies, controlling cross-site request behavior.
pub(all) enum SameSiteOption {
  Lax
  Strict
  SameSiteNone
} derive(Debug, Eq)

///|
pub impl Show for SameSiteOption with fn output(self, logger) {
  match self {
    Lax => logger.write_string("Lax")
    Strict => logger.write_string("Strict")
    SameSiteNone => logger.write_string("SameSiteNone")
  }
}

///|
pub impl ToJson for SameSiteOption with fn to_json(self : SameSiteOption) -> Json {
  match self {
    Lax => "lax"
    Strict => "strict"
    SameSiteNone => "none"
  }
}

///|
/// Represents an HTTP cookie with its name, value, and optional attributes.
pub(all) struct CookieItem {
  /// Cookie name (the key in `name=value`).
  name : String
  /// Cookie value.
  value : String
  /// Expiry in seconds from now; `0` deletes the cookie.
  max_age : Int?
  /// URL path scope for which the browser sends this cookie.
  path : String?
  /// Domain scope for which the browser sends this cookie.
  domain : String?
  /// If `true`, the cookie is only sent over HTTPS.
  secure : Bool?
  /// If `true`, JavaScript cannot access the cookie (`document.cookie`).
  http_only : Bool?
  /// Cross-site request policy (`Lax`, `Strict`, or `SameSiteNone`).
  same_site : SameSiteOption?
} derive(Eq, Debug)

///|
/// Creates a new `CookieItem` with the given name, value, and optional attributes.
pub fn CookieItem::CookieItem(
  name~ : String,
  value~ : String,
  max_age? : Int,
  path? : String,
  domain? : String,
  secure? : Bool,
  http_only? : Bool,
  same_site? : SameSiteOption,
) -> CookieItem {
  { name, value, max_age, path, domain, secure, http_only, same_site }
}

///|
fn sanitize_cookie_value(s : String) -> String {
  if s.contains("\r") || s.contains("\n") || s.contains(";") {
    let buf = StringBuilder::new()
    for c in s {
      if c != '\r' && c != '\n' && c != ';' {
        buf.write_char(c)
      }
    }
    buf.to_string()
  } else {
    s
  }
}

///|
pub impl Show for CookieItem with fn output(self, logger) -> Unit {
  logger.write_string(sanitize_cookie_value(self.name))
  logger.write_char('=')
  logger.write_string(sanitize_cookie_value(self.value))
  if self.max_age is Some(max_age) {
    logger.write_string("; Max-Age=")
    logger.write_string(max_age.to_string())
  }
  if self.path is Some(path) {
    logger.write_string("; Path=")
    logger.write_string(path)
  }
  if self.domain is Some(domain) {
    logger.write_string("; Domain=")
    logger.write_string(domain)
  }
  if self.secure == Some(true) {
    logger.write_string("; Secure")
  }
  if self.http_only == Some(true) {
    logger.write_string("; HttpOnly")
  }
  if self.same_site is Some(same_site) {
    logger.write_string("; SameSite=")
    logger.write_string(same_site.to_string())
  }
}

///|
pub impl Show for CookieItem with fn to_string(self : CookieItem) -> String {
  let buf = StringBuilder()
  self.output(buf)
  buf.to_string()
}

///|
/// Serializes an array of cookie items into a semicolon-separated string.
pub fn cookie_to_string(cookie : Array[CookieItem]) -> String {
  cookie.map(x => x.to_string()).join(";")
}

///|
/// Parses a raw cookie header string into a map of cookie names to `CookieItem` values.
pub fn parse_cookie(cookie : StringView) -> Map[String, CookieItem] {
  fn dequote(value : StringView) -> StringView {
    if value is ['"', .. rest, '"'] {
      rest
    } else {
      value
    }
  }

  let res = Map([])
  let mut last_cookie_item : (String, CookieItem)? = None
  fn on_key_value(key : StringView, value : StringView) -> Unit {
    let key = key.to_owned()
    let value = dequote(value).to_owned()
    if last_cookie_item is Some((name, item)) {
      let new_item = lexscan key with longest {
        re"^(?i:path)$" => { ..item, path: Some(value) }
        re"^(?i:domain)$" => { ..item, domain: Some(value) }
        re"^(?i:max-age)$" =>
          {
            ..item,
            max_age: try @string.parse_int(value) catch {
              _ => None
            } noraise {
              x => Some(x)
            },
          }
        re"^(?i:secure)$" => { ..item, secure: Some(true) }
        re"^(?i:httponly)$" => { ..item, http_only: Some(true) }
        re"^(?i:samesite)$" => {
          let same_site = lexscan value with longest {
            re"^(?i:lax)$" => Some(Lax)
            re"^(?i:strict)$" => Some(Strict)
            re"^(?i:none)$" => Some(SameSiteNone)
            _ => None
          }
          { ..item, same_site, }
        }
        _ => item
      }
      if !physical_equal(new_item, item) {
        res.set(name, new_item)
        last_cookie_item = Some((name, new_item))
        return
      }
    }
    let item = CookieItem(name=key, value~)
    res.set(key, item)
    last_cookie_item = Some((key, item))
  }

  for curr = cookie {
    // TODO: more spec compliance
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#attributes
    lexscan curr with longest {
      (re"^[ \t]+", after=rest) => continue rest
      (
        (re"^[^ \t=;]([ \t]*[^ \t=;])*" as key) +
        re"[ \t]*" +
        re"=" +
        re"[ \t]*" +
        (re"[^ \t;]([ \t]*[^ \t;])*" as value) +
        re"[ \t]*" +
        re";?",
        after=rest,
      ) => {
        on_key_value(key, value)
        continue rest
      }
      (
        (re"^[^ \t=;]([ \t]*[^ \t=;])*" as key) +
        re"[ \t]*" +
        re"(=[ \t]*)?" +
        re";?",
        after=rest,
      ) => {
        on_key_value(key, "")
        continue rest
      }
      _ => break
    }
  }
  res
}
