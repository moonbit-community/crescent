// Per-connection lifecycle for the websocket runtime: handshake, the
// Open -> Message* -> Close handler dispatch loop, message I/O, and
// shutdown handling. Calls into the hub primitives in websocket/hub.mbt.

///|
const NATIVE_WS_READ_TIMEOUT_REASON : String = "websocket read timeout"

///|
const NATIVE_WS_MESSAGE_TOO_BIG_REASON : String = "websocket message too big"

///|
const NATIVE_WS_SERVER_SHUTDOWN_REASON : String = "websocket server shutdown"

///|
async fn write_native_ws_outgoing(
  ws : @async_websocket.Conn,
  outgoing : @async.Queue[NativeWebSocketOutbound],
) -> Unit {
  for ;; {
    let next = outgoing.get() catch { _ => break }
    match next {
      SendText(text) => ws.send_text(text)
      SendBinary(data) => ws.send_binary(data)
    }
  }
}

///|
async fn recv_native_ws_message(
  ws : @async_websocket.Conn,
  read_timeout_ms : Int?,
) -> @async_websocket.Message? {
  match read_timeout_ms {
    Some(read_timeout_ms) =>
      match
        @async.with_timeout_opt(read_timeout_ms, () => {
          try ws.recv() catch {
            err => Err(err)
          } noraise {
            v => Ok(v)
          }
        }) {
        Some(Ok(message)) => Some(message)
        Some(Err(@async_websocket.ConnectionClosed(_, _))) => None
        Some(Err(err)) => raise err
        None => {
          ignore(
            try
              ws.send_close(
                code=GoingAway,
                reason=NATIVE_WS_READ_TIMEOUT_REASON,
              )
            catch {
              err => Err(err)
            } noraise {
              v => Ok(v)
            },
          )
          None
        }
      }
    None => {
      let message_result : Result[@async_websocket.Message, Error] = try
        ws.recv()
      catch {
        err => Err(err)
      } noraise {
        v => Ok(v)
      }
      match message_result {
        Ok(message) => Some(message)
        Err(@async_websocket.ConnectionClosed(_, _)) => None
        Err(err) => raise err
      }
    }
  }
}

///|
fn decode_native_ws_message(
  message_kind : @async_websocket.MessageKind,
  contents : Bytes,
) -> WebSocketAggregatedMessage {
  match message_kind {
    Text =>
      Text(
        @utf8.decode(contents) catch {
          _ => abort("validated websocket text message must be valid UTF-8")
        },
      )
    Binary => Binary(contents)
  }
}

///|
fn next_native_ws_message_chunk_size(limit : Int, total : Int) -> Int {
  let remaining = limit - total
  if remaining >= 1024 {
    1024
  } else {
    remaining + 1
  }
}

///|
fn native_ws_chunk_exceeds_limit(
  limit : Int,
  total : Int,
  chunk_length : Int,
) -> Bool {
  chunk_length > limit - total
}

///|
async fn read_native_ws_message_contents(
  ws : @async_websocket.Conn,
  message : @async_websocket.Message,
  max_message_bytes : Int?,
) -> WebSocketAggregatedMessage? {
  match max_message_bytes {
    None =>
      Some(
        match message.kind {
          Text => Text(message.read_all().text())
          Binary => Binary(message.read_all().binary())
        },
      )
    Some(limit) => {
      let buffer = Buffer()
      let mut total = 0
      for ;; {
        let next_chunk_size = next_native_ws_message_chunk_size(limit, total)
        guard message.read_some(max_len=next_chunk_size) is Some(chunk) else {
          return Some(decode_native_ws_message(message.kind, buffer.contents()))
        }
        if native_ws_chunk_exceeds_limit(limit, total, chunk.length()) {
          ignore(
            try
              ws.send_close(
                code=MessageTooBig,
                reason=NATIVE_WS_MESSAGE_TOO_BIG_REASON,
              )
            catch {
              err => Err(err)
            } noraise {
              v => Ok(v)
            },
          )
          return None
        }
        total += chunk.length()
        buffer.write_bytes(chunk)
      }
    }
  }
}

///|
async fn send_native_ws_shutdown_close(ws : @async_websocket.Conn) -> Unit {
  ignore(
    try
      @async.protect_from_cancel(resume_on_cancel=true, () => {
        ws.send_close(code=GoingAway, reason=NATIVE_WS_SERVER_SHUTDOWN_REASON)
      })
    catch {
      err => Err(err)
    } noraise {
      v => Ok(v)
    },
  )
}

///|
fn normalize_native_websocket_request_headers(
  headers : Map[String, String],
) -> Map[String, String] {
  let normalized : Map[String, String] = {}
  headers.each((key, value) => {
    let normalized_value = match key.to_lower() {
      "connection" =>
        value.split(",").map(token => token.trim()).to_array().join(", ")
      "upgrade" | "sec-websocket-version" | "sec-websocket-key" =>
        value.trim().to_owned()
      _ => value
    }
    normalized.set(key, normalized_value)
  })
  normalized
}

///|
fn normalize_native_websocket_request(request : @http.Request) -> @http.Request {
  {
    meth: request.meth,
    path: request.path,
    headers: normalize_native_websocket_request_headers(request.headers),
  }
}

///|
/// Runs one accepted WebSocket upgrade to completion: handshake, hub
/// registration, the `Open → Message* → Close` user-handler lifecycle,
/// and cleanup.
///
/// Called by `App::handle_request`'s WebSocket dispatch branch. Unlike
/// HTTP `handle_request` (which runs once per request), this function is
/// long-lived — it returns only when the peer loop exits (client close,
/// read timeout, oversized message) or when the enclosing task group is
/// cancelled (server shutdown).
///
/// Lifecycle phases:
///
///   1. **Handshake.** `@async_websocket.from_http_server` validates the upgrade
///      headers and writes the `101 Switching Protocols` response.
///      `InvalidHandshake` is swallowed silently — no Open/Close events fire,
///      the underlying `conn` closes via `defer ws.close()`. Other errors
///      propagate (surfaces to the keep-alive loop, which closes the conn).
///   2. **Registration.** Allocate a connection_id, create a bounded
///      outbound queue (`Blocking(outgoing_queue_capacity)`), register with
///      the hub. The `overflow_policy` is recorded in the hub so
///      `ws_publish` can drop oldest/latest on a full queue.
///   3. **Writer task.** `write_native_ws_outgoing` is spawned as a sibling
///      inside the task group: it drains `outgoing` into the socket. It
///      exits when `outgoing.close()` fires (normal exit) or when the task
///      group is cancelled.
///   4. **Peer loop.** Fire `Open` once, then loop: `recv_native_ws_message`
///      reads a frame header (respecting `read_timeout_ms`);
///      `read_native_ws_message_contents` aggregates continuation frames up
///      to `max_message_bytes` (oversized → 1009 close sent internally,
///      returns None → we break). Each complete message fires `Message`.
///      Either helper returning None ends the session.
///   5. **Shutdown.** `outgoing.close()` signals the writer task to exit.
///      `handler(Close)` fires (see invariants below).
///
/// Key invariants:
///
/// - **`Close` fires exactly once whenever `Open` did.** Normal exit reaches
///   the final `handler(Close(...))` at the bottom; error/cancellation goes
///   through the `catch` block, which calls `Close` and re-raises. If the
///   handshake fails (`InvalidHandshake`), neither Open nor Close fires.
///
/// - **Cancellation sends a polite `GoingAway` close frame before the
///   socket dies.** `send_native_ws_shutdown_close` uses
///   `protect_from_cancel` so the frame actually reaches the wire even
///   though we're already in a cancelled task. Without this, clients would
///   see an abrupt TCP reset on server shutdown instead of a 1001 close.
///
/// - **The two `defer`s guarantee cleanup on every path,** including user
///   handler exceptions during `Close`. `defer ws.close()` drops the socket;
///   `defer unregister_native_ws_connection` removes the hub entry,
///   channel memberships, and any subscriptions the user added during
///   `Close`. Running `unregister` only on the happy path would leak those
///   on any exception inside the Close handler.
pub async fn handle_route_async(
  runtime_id : String,
  request : @http.Request,
  conn : @http.ServerConnection,
  handler : WebSocketHandler,
  params : Map[String, String],
  max_message_bytes : Int?,
  outgoing_queue_capacity : Int,
  overflow_policy : NativeWebSocketOverflowPolicy,
  read_timeout_ms : Int?,
) -> Unit {
  // -------------------------------------------------------------------------
  // Phase 1: Handshake
  // -------------------------------------------------------------------------
  // normalize_native_websocket_request canonicalizes header casing/whitespace
  // so from_http_server's strict RFC 6455 validation accepts real-world
  // clients (browsers tend to use "Upgrade, keep-alive" etc.).
  let ws = try
    @async_websocket.from_http_server(
      normalize_native_websocket_request(request),
      conn,
    )
  catch {
    // Handshake failed: return silently. `conn` is still owned by the
    // caller's keep-alive loop, which will close it. We do NOT want to send
    // a Close event to the user handler (Open never fired).
    @async_websocket.InvalidHandshake(_) => return
    // Transport-level error during handshake (e.g. socket write failed):
    // bubble up, let the caller close `conn`.
    err => raise err
  } noraise {
    ws => ws
  }
  // Socket closed on every exit path from here on.
  defer ws.close()

  // -------------------------------------------------------------------------
  // Phase 2: Hub registration
  // -------------------------------------------------------------------------
  let hub = ensure_native_ws_hub(runtime_id)
  let connection_id = next_native_ws_connection_id(runtime_id, hub)
  // Bounded outbound queue. Blocking(cap) means publishers either wait for
  // room or invoke overflow_policy (DropOldest/DropLatest) via ws_publish.
  let outgoing = @async.Queue(kind=Blocking(outgoing_queue_capacity))
  register_native_ws_connection(
    runtime_id, connection_id, outgoing, overflow_policy,
  )
  // Unconditional cleanup — runs even if the session loop or the Close
  // handler exits abnormally (e.g. via async cancellation). Without this
  // `defer`, a failing Close handler would leak the connection entry,
  // channel memberships, and any subscriptions added during Close.
  defer unregister_native_ws_connection(connection_id)

  // -------------------------------------------------------------------------
  // Phase 3 + 4: Writer task + peer loop
  // -------------------------------------------------------------------------
  // Task group scope: the writer task is a child, the peer loop is the
  // group's main body. When the main body exits, the group waits for the
  // writer (which outgoing.close() nudges to completion). If either task
  // raises, the group cancels the sibling and re-raises to our `catch`.
  @async.with_task_group(group => {
    group.spawn_bg(() => write_native_ws_outgoing(ws, outgoing))
    // Open fires exactly once, before the first Message.
    handler(Open(snapshot_native_ws_peer(connection_id, params)))
    for ;; {
      // recv_native_ws_message returns None on graceful close or read
      // timeout (it sends the appropriate close frame internally).
      let message = match recv_native_ws_message(ws, read_timeout_ms) {
        Some(message) => message
        None => break
      }
      // Re-snapshot the peer per-message: params are immutable but this
      // yields a fresh owned WebSocketPeer view the handler can retain.
      let peer = snapshot_native_ws_peer(connection_id, params)
      // read_native_ws_message_contents returns None when the aggregated
      // payload would exceed max_message_bytes; it has already sent a 1009
      // MessageTooBig close frame, so we just exit the loop.
      match read_native_ws_message_contents(ws, message, max_message_bytes) {
        Some(aggregated_message) => handler(Message(peer, aggregated_message))
        None => break
      }
    }
    // Tell the writer task there will be no more messages. It drains
    // anything already enqueued, then exits, letting the group close.
    outgoing.close()
  }) catch {
    err => {
      // Cancellation path (server shutdown): send a 1001 GoingAway close
      // frame so clients see an orderly shutdown instead of a TCP reset.
      // The close helper itself is cancel-protected.
      if @async.is_cancellation_error(err) {
        send_native_ws_shutdown_close(ws)
      }
      // Close still fires on the error path — paired with the Open above.
      handler(Close(snapshot_native_ws_peer(connection_id, params)))
      raise err
    }
  }
  // Normal-exit Close. Paired with the catch-path Close above, this ensures
  // Close fires exactly once per Open regardless of how the session ended.
  handler(Close(snapshot_native_ws_peer(connection_id, params)))
}
