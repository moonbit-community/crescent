///|
/// Returns a middleware that enforces a fixed-window rate limit.
///
/// Returns `429 Too Many Requests` with a `Retry-After` header when the limit
/// is exceeded. The limiter is global (per-process), not per-IP.
///
/// - `requests_per_window` — maximum requests allowed per window.
/// - `window_ms` — window duration in milliseconds.
pub fn rate_limit(
  requests_per_window~ : Int,
  window_ms~ : Int,
) -> @crescent.Middleware {
  let window_start : Ref[Int64] = Ref(0L)
  let request_count : Ref[Int] = Ref(0)
  (_event, next) => {
    let now = @async.now()
    // Reset window if expired
    if now - window_start.val >= window_ms.to_int64() {
      window_start.val = now
      request_count.val = 0
    }
    request_count.val += 1
    if request_count.val > requests_per_window {
      let remaining_ms = window_ms.to_int64() - (now - window_start.val)
      let retry_after = (remaining_ms / 1000L + 1L).to_string()
      @crescent.HttpResponse(status_code=TooManyRequests)
      .header("Retry-After", retry_after)
      .body("Too Many Requests")
      .to_responder()
    } else {
      next()
    }
  }
}
