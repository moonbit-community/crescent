///|
/// Represents the host component of a URI, which is either an IPv6 address
/// enclosed in brackets or a registered name (including IPv4 addresses).
pub enum Host {
  IPv6Address(StringView)
  RegName(StringView)
} derive(Eq, Debug)

///|
pub extend Host with Eq::{not_equal, equal}

///|
pub extend Host with Debug::{to_repr}

///|
/// The authority component of a URI, comprising an optional userinfo, a host,
/// and an optional port number (e.g. `user:pass@example.com:8080`).
pub struct Authority {
  /// Userinfo component before `@` (e.g., `user:pass`), if present.
  mut userinfo : StringView?
  /// Host component: either a domain name (`RegName`) or IPv6 address.
  mut host : Host
  /// Port number, if explicitly specified in the URI.
  mut port : Int?
} derive(Eq, Debug)

///|
pub extend Authority with Eq::{not_equal, equal}

///|
pub extend Authority with Debug::{to_repr}

///|
/// A parsed URI following RFC 3986, containing an optional scheme, authority,
/// path segments, query, and fragment.
pub struct Uri {
  /// URI scheme (e.g., `http`, `https`, `ftp`), if present.
  mut scheme : StringView?
  /// Authority component (`userinfo@host:port`), if present.
  mut authority : Authority?
  /// Path segments split by `/`. A leading `/` produces an empty first segment.
  path : Array[StringView]
  /// Query string after `?`, if present (without the `?`).
  mut query : StringView?
  /// Fragment after `#`, if present (without the `#`).
  mut fragment : StringView?
} derive(Eq, Debug)

///|
pub extend Uri with Eq::{not_equal, equal}

///|
pub extend Uri with Debug::{to_repr}

///|
/// Errors that can occur during URI parsing, indicating the specific component
/// that failed validation.
pub suberror ParseError {
  InvalidScheme(StringView)
  InvalidHeirPart(StringView)
  InvalidPercentEncoding(StringView)
  MissingColon
  MissingScheme
  InvalidSegment(StringView)
  InvalidSchemeOrSegment(StringView)
  Invalid(StringView)
}

///|
/// Returns the prefix of `self` up to (but not including) where `other` starts.
/// Both views must originate from the same underlying string, with `other`
/// being a suffix of `self`.
fn StringView::slice_before(
  self : StringView,
  other : StringView,
) -> StringView {
  self[:self.length() - other.length()]
}
