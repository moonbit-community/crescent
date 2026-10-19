///|
/// Returns a middleware that sets common security response headers.
///
/// The four base headers (X-Content-Type-Options, X-Frame-Options,
/// X-XSS-Protection, Referrer-Policy) are always applied as safe defaults.
///
/// The three policy headers are opt-in (default `""` = disabled) to avoid
/// breaking existing apps that rely on inline scripts or third-party assets:
///
/// - `hsts` — `Strict-Transport-Security` value. Only meaningful over TLS.
/// - `csp` — `Content-Security-Policy` value.
/// - `permissions_policy` — `Permissions-Policy` value.
///
/// Headers already set by a handler or inner middleware are preserved (not
/// overwritten) so that per-route policies take precedence.
pub fn security_headers(
  hsts~ : String = "",
  csp~ : String = "",
  permissions_policy~ : String = "",
) -> @crescent.Middleware {
  (event, next) => {
    let res = next()
    let h = event.res.headers
    @httputil.set_missing_header_case_insensitive(
      h, "X-Content-Type-Options", "nosniff",
    )
    @httputil.set_missing_header_case_insensitive(h, "X-Frame-Options", "DENY")
    @httputil.set_missing_header_case_insensitive(h, "X-XSS-Protection", "0")
    @httputil.set_missing_header_case_insensitive(
      h, "Referrer-Policy", "strict-origin-when-cross-origin",
    )
    if hsts != "" {
      @httputil.set_missing_header_case_insensitive(
        h, "Strict-Transport-Security", hsts,
      )
    }
    if csp != "" {
      @httputil.set_missing_header_case_insensitive(
        h, "Content-Security-Policy", csp,
      )
    }
    if permissions_policy != "" {
      @httputil.set_missing_header_case_insensitive(
        h, "Permissions-Policy", permissions_policy,
      )
    }
    res
  }
}
