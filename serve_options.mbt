///|
/// Error type for invalid native server configuration values.
pub suberror NativeServeError {
  InvalidMaxConnections(Int)
  InvalidMaxRequestBodyBytes(Int)
  InvalidRequestBodyReadTimeoutMs(Int)
  InvalidHandlerTimeoutMs(Int)
  InvalidShutdownTimeoutMs(Int)
  InvalidWebSocketMaxMessageBytes(Int)
  InvalidWebSocketOutgoingQueueCapacity(Int)
  InvalidWebSocketReadTimeoutMs(Int)
} derive(Debug, ToJson)

///|
/// Configuration options for the native async HTTP server runtime.
/// The constructor validates all values eagerly and raises on invalid input.
pub struct NativeServeOptions {
  /// Maximum concurrent TCP connections; `None` means unlimited.
  max_connections : Int?
  /// Maximum request body size in bytes; exceeding yields `413 Request Entity Too Large`.
  max_request_body_bytes : Int?
  /// Timeout for reading the request body in milliseconds; exceeding yields `408 Request Timeout`.
  request_body_read_timeout_ms : Int?
  /// Timeout for the handler + middleware pipeline in milliseconds; exceeding yields `504 Gateway Timeout`.
  handler_timeout_ms : Int?
  /// Graceful shutdown drain period in milliseconds; `None` means immediate cancellation.
  shutdown_timeout_ms : Int?
  /// Maximum buffered outbound WebSocket messages per connection (default: 256).
  websocket_outgoing_queue_capacity : Int?
  /// Policy when the outbound WebSocket queue is full (`DropOldest` or `DropLatest`).
  websocket_overflow_policy : @ws.NativeWebSocketOverflowPolicy?
  /// Timeout for the next inbound WebSocket message in milliseconds; exceeding closes the connection.
  websocket_read_timeout_ms : Int?
  /// Maximum inbound WebSocket message size in bytes; exceeding closes with `1009 Message Too Big`.
  websocket_max_message_bytes : Int?
}

///|
/// Validate and construct `NativeServeOptions` from optional tuning
/// parameters. Each parameter defaults to `None` (moon fmt infers that
/// from the `?` markers) and is individually range-checked; raises if
/// any value is out of range.
pub fn NativeServeOptions::NativeServeOptions(
  max_connections? : Int,
  max_request_body_bytes? : Int,
  request_body_read_timeout_ms? : Int,
  handler_timeout_ms? : Int,
  shutdown_timeout_ms? : Int,
  websocket_outgoing_queue_capacity? : Int,
  websocket_overflow_policy? : @ws.NativeWebSocketOverflowPolicy,
  websocket_read_timeout_ms? : Int,
  websocket_max_message_bytes? : Int,
) -> NativeServeOptions raise {
  if max_connections is Some(v) {
    guard v > 0 else { raise NativeServeError::InvalidMaxConnections(v) }
  }
  if max_request_body_bytes is Some(v) {
    guard v >= 0 else { raise NativeServeError::InvalidMaxRequestBodyBytes(v) }
  }
  if request_body_read_timeout_ms is Some(v) {
    guard v > 0 else {
      raise NativeServeError::InvalidRequestBodyReadTimeoutMs(v)
    }
  }
  if handler_timeout_ms is Some(v) {
    guard v > 0 else { raise NativeServeError::InvalidHandlerTimeoutMs(v) }
  }
  if shutdown_timeout_ms is Some(v) {
    guard v > 0 else { raise NativeServeError::InvalidShutdownTimeoutMs(v) }
  }
  if websocket_max_message_bytes is Some(v) {
    guard v >= 0 else {
      raise NativeServeError::InvalidWebSocketMaxMessageBytes(v)
    }
  }
  if websocket_outgoing_queue_capacity is Some(v) {
    guard v > 0 else {
      raise NativeServeError::InvalidWebSocketOutgoingQueueCapacity(v)
    }
  }
  if websocket_read_timeout_ms is Some(v) {
    guard v > 0 else {
      raise NativeServeError::InvalidWebSocketReadTimeoutMs(v)
    }
  }
  {
    max_connections,
    max_request_body_bytes,
    request_body_read_timeout_ms,
    handler_timeout_ms,
    shutdown_timeout_ms,
    websocket_outgoing_queue_capacity,
    websocket_overflow_policy,
    websocket_read_timeout_ms,
    websocket_max_message_bytes,
  }
}

///|
test "NativeServeOptions accepts all defaults" {
  let opts = NativeServeOptions()
  debug_inspect(opts.max_connections, content="None")
}

///|
test "NativeServeOptions accepts valid values" {
  let opts = NativeServeOptions(
    max_connections=5,
    max_request_body_bytes=1024,
    request_body_read_timeout_ms=100,
    handler_timeout_ms=5000,
    shutdown_timeout_ms=5000,
    websocket_outgoing_queue_capacity=10,
    websocket_overflow_policy=DropLatest,
    websocket_read_timeout_ms=100,
    websocket_max_message_bytes=1024,
  )
  debug_inspect(opts.max_connections, content="Some(5)")
  debug_inspect(opts.max_request_body_bytes, content="Some(1024)")
}

///|
test "NativeServeOptions accepts zero max_request_body_bytes" {
  let opts = NativeServeOptions(max_request_body_bytes=0)
  debug_inspect(opts.max_request_body_bytes, content="Some(0)")
}

///|
test "NativeServeOptions accepts zero websocket_max_message_bytes" {
  let opts = NativeServeOptions(websocket_max_message_bytes=0)
  debug_inspect(opts.websocket_max_message_bytes, content="Some(0)")
}

///|
test "NativeServeOptions rejects zero max_connections" {
  @test.assert_raise(() => NativeServeOptions(max_connections=0))
}

///|
test "NativeServeOptions rejects negative max_connections" {
  @test.assert_raise(() => NativeServeOptions(max_connections=-1))
}

///|
test "NativeServeOptions rejects negative max_request_body_bytes" {
  @test.assert_raise(() => NativeServeOptions(max_request_body_bytes=-1))
}

///|
test "NativeServeOptions rejects zero request_body_read_timeout_ms" {
  @test.assert_raise(() => NativeServeOptions(request_body_read_timeout_ms=0))
}

///|
test "NativeServeOptions rejects negative request_body_read_timeout_ms" {
  @test.assert_raise(() => NativeServeOptions(request_body_read_timeout_ms=-1))
}

///|
test "NativeServeOptions rejects zero handler_timeout_ms" {
  @test.assert_raise(() => NativeServeOptions(handler_timeout_ms=0))
}

///|
test "NativeServeOptions rejects negative handler_timeout_ms" {
  @test.assert_raise(() => NativeServeOptions(handler_timeout_ms=-1))
}

///|
test "NativeServeOptions rejects zero shutdown_timeout_ms" {
  @test.assert_raise(() => NativeServeOptions(shutdown_timeout_ms=0))
}

///|
test "NativeServeOptions rejects negative shutdown_timeout_ms" {
  @test.assert_raise(() => NativeServeOptions(shutdown_timeout_ms=-1))
}

///|
test "NativeServeOptions rejects negative websocket_max_message_bytes" {
  @test.assert_raise(() => NativeServeOptions(websocket_max_message_bytes=-1))
}

///|
test "NativeServeOptions rejects zero websocket_outgoing_queue_capacity" {
  @test.assert_raise(() => {
    NativeServeOptions(websocket_outgoing_queue_capacity=0)
  })
}

///|
test "NativeServeOptions rejects negative websocket_outgoing_queue_capacity" {
  @test.assert_raise(() => {
    NativeServeOptions(websocket_outgoing_queue_capacity=-1)
  })
}

///|
test "NativeServeOptions rejects zero websocket_read_timeout_ms" {
  @test.assert_raise(() => NativeServeOptions(websocket_read_timeout_ms=0))
}

///|
test "NativeServeOptions rejects negative websocket_read_timeout_ms" {
  @test.assert_raise(() => NativeServeOptions(websocket_read_timeout_ms=-1))
}
