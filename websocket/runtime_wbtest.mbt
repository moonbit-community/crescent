// Whitebox tests for the websocket runtime: drop-policy enqueue, hub
// register/cleanup, ws_subscribe/unsubscribe, message decode/chunking,
// plus one lifecycle invariant test that drives handle_route_async
// directly (no App + serve scaffolding) so it can read internal hub
// state without a public test-only probe.
// Higher-level tests that drive App + serve_on with multiple clients
// live in root websocket_async_native_wbtest.mbt.

///|
suberror DirectLifecycleSocketBindUnavailable

///|
suberror DirectLifecycleNotReady

///|
async fn allocate_direct_lifecycle_server() -> @http.Server {
  let addr = @socket.Addr::parse("127.0.0.1:0") catch {
    _ => raise DirectLifecycleSocketBindUnavailable
  }
  let bind_check : Result[@http.Server, Error] = try
    @http.Server(addr, reuse_addr=true)
  catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  match bind_check {
    Ok(server) => server
    Err(@os_error.OSError(errno, ..)) if errno == 1 =>
      raise DirectLifecycleSocketBindUnavailable
    Err(@os_error.OSError(_) as err) if err.is_EACCES() =>
      raise DirectLifecycleSocketBindUnavailable
    Err(err) => fail("unexpected bind check failure: \{err}")
  }
}

///|
/// Drives handle_route_async directly (no App, no serve_on) so the
/// Close-event handler can inspect internal hub state without going
/// through a public probe. Verifies the runtime's documented
/// invariants for the Close phase:
///   - the connection is still registered in the hub
///   - the outgoing queue has already been closed (try_put raises)
///
/// The corresponding public-API behavior (channels are still populated
/// before unregister; cleanup happens after the user handler returns)
/// is covered by the App-driven test in root.
async test "outgoing queue is closed before Close handler fires" {
  let runtime_id = "test-direct-close-order"
  let close_saw_registered : Ref[Bool?] = Ref(None)
  let close_saw_queue_closed : Ref[Bool?] = Ref(None)
  let handler : WebSocketHandler = event => {
    match event {
      Close(peer) =>
        match resolve_native_ws_connection(peer.connection_id) {
          Some((_, connection)) => {
            close_saw_registered.val = Some(true)
            let result : Result[Bool, Error] = try
              connection.outgoing.try_put(SendBinary(b""))
            catch {
              err => Err(err)
            } noraise {
              v => Ok(v)
            }
            close_saw_queue_closed.val = Some(
              match result {
                Err(_) => true
                _ => false
              },
            )
          }
          None => {
            close_saw_registered.val = Some(false)
            close_saw_queue_closed.val = Some(false)
          }
        }
      _ => ()
    }
  }
  defer cleanup_runtime(runtime_id)
  @async.with_task_group(group => {
    let server = allocate_direct_lifecycle_server()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      for ;; {
        let conn_result : Result[(@http.ServerConnection, @socket.Addr), Error] = try
          server.accept()
        catch {
          err => Err(err)
        } noraise {
          v => Ok(v)
        }
        match conn_result {
          Err(_) => break
          Ok((conn, _addr)) =>
            group.spawn_bg(allow_failure=true, () => {
              let req = conn.read_request()
              handle_route_async(
                runtime_id,
                req,
                conn,
                handler,
                {},
                None,
                256,
                DropOldest,
                None,
              )
            })
        }
      }
    })
    let client = @async_websocket.connect("ws://127.0.0.1:\{port}/")
    defer client.close()
    @async.retry(FixedDelay(20), max_retry=50, () => {
      // Scope the readiness guard to THIS runtime's hub so concurrent
      // tests / leaked connections elsewhere can't false-positive it.
      let ready = match native_ws_hubs.get(runtime_id) {
        Some(hub) => !hub.connections.is_empty()
        None => false
      }
      guard ready else { raise DirectLifecycleNotReady }
    })
    client.send_close()
    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard close_saw_queue_closed.val is Some(_) else {
        raise DirectLifecycleNotReady
      }
    })
    inspect(close_saw_registered.val, content="Some(true)")
    inspect(close_saw_queue_closed.val, content="Some(true)")
    server.close()
  }) catch {
    DirectLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
fn test_native_ws_connection(
  capacity : Int,
  overflow_policy : NativeWebSocketOverflowPolicy,
) -> NativeWebSocketConnection {
  {
    outgoing: Queue(kind=Blocking(capacity)),
    overflow_policy,
    subscribed_channels: Map([]),
  }
}

///|
test "native websocket message limit helpers handle int max boundaries" {
  let max_int = 2_147_483_647
  inspect(next_native_ws_message_chunk_size(max_int, 0), content="1024")
  inspect(native_ws_chunk_exceeds_limit(max_int, max_int, 1), content="true")
  inspect(
    native_ws_chunk_exceeds_limit(max_int, max_int - 1, 1),
    content="false",
  )
}

///|
test "enqueue_native_ws_outgoing_to_connection drops oldest when configured" {
  let connection = test_native_ws_connection(2, DropOldest)
  enqueue_native_ws_outgoing_to_connection(connection, SendText("one"))
  enqueue_native_ws_outgoing_to_connection(connection, SendText("two"))
  enqueue_native_ws_outgoing_to_connection(connection, SendText("three"))
  match connection.outgoing.try_get() {
    Some(SendText(text)) => inspect(text, content="two")
    Some(_) => fail("unexpected first queued websocket message kind")
    None => fail("expected first queued websocket message")
  }
  match connection.outgoing.try_get() {
    Some(SendText(text)) => inspect(text, content="three")
    Some(_) => fail("unexpected second queued websocket message kind")
    None => fail("expected second queued websocket message")
  }
  inspect(connection.outgoing.try_get() is None, content="true")
}

///|
test "enqueue_native_ws_outgoing_to_connection drops latest when configured" {
  let connection = test_native_ws_connection(2, DropLatest)
  enqueue_native_ws_outgoing_to_connection(connection, SendText("one"))
  enqueue_native_ws_outgoing_to_connection(connection, SendText("two"))
  enqueue_native_ws_outgoing_to_connection(connection, SendText("three"))
  match connection.outgoing.try_get() {
    Some(SendText(text)) => inspect(text, content="one")
    Some(_) => fail("unexpected first queued websocket message kind")
    None => fail("expected first queued websocket message")
  }
  match connection.outgoing.try_get() {
    Some(SendText(text)) => inspect(text, content="two")
    Some(_) => fail("unexpected second queued websocket message kind")
    None => fail("expected second queued websocket message")
  }
  inspect(connection.outgoing.try_get() is None, content="true")
}

///|
test "ensure_native_ws_hub creates new hub for new runtime id" {
  let runtime_id = "test-ensure-hub-new"
  let hub = ensure_native_ws_hub(runtime_id)
  inspect(hub.connections.is_empty(), content="true")
  inspect(hub.connection_counter.val, content="0")
  cleanup_runtime(runtime_id)
}

///|
test "ensure_native_ws_hub returns existing hub for same runtime id" {
  let runtime_id = "test-ensure-hub-existing"
  let hub1 = ensure_native_ws_hub(runtime_id)
  hub1.connection_counter.val = 42
  let hub2 = ensure_native_ws_hub(runtime_id)
  inspect(hub2.connection_counter.val, content="42")
  cleanup_runtime(runtime_id)
}

///|
test "next_native_ws_connection_id increments counter and formats id" {
  let runtime_id = "test-conn-id"
  let hub = ensure_native_ws_hub(runtime_id)
  let id1 = next_native_ws_connection_id(runtime_id, hub)
  inspect(id1, content="test-conn-id:1")
  let id2 = next_native_ws_connection_id(runtime_id, hub)
  inspect(id2, content="test-conn-id:2")
  let id3 = next_native_ws_connection_id(runtime_id, hub)
  inspect(id3, content="test-conn-id:3")
  cleanup_runtime(runtime_id)
}

///|
test "register_native_ws_connection makes connection resolvable" {
  let runtime_id = "test-register"
  let connection_id = "test-register:1"
  let outgoing = @async.Queue(kind=Blocking(10))
  register_native_ws_connection(runtime_id, connection_id, outgoing, DropOldest)
  inspect(
    resolve_native_ws_connection(connection_id) is Some(_),
    content="true",
  )
  inspect(connection_is_registered(connection_id), content="true")
  cleanup_runtime(runtime_id)
}

///|
test "unregister_native_ws_connection makes connection unresolvable" {
  let runtime_id = "test-unregister"
  let connection_id = "test-unregister:1"
  let outgoing = @async.Queue(kind=Blocking(10))
  register_native_ws_connection(runtime_id, connection_id, outgoing, DropOldest)
  inspect(connection_is_registered(connection_id), content="true")
  unregister_native_ws_connection(connection_id)
  inspect(connection_is_registered(connection_id), content="false")
  inspect(
    resolve_native_ws_connection(connection_id) is Some(_),
    content="false",
  )
}

///|
test "unregister_native_ws_connection removes hub when last connection removed" {
  let runtime_id = "test-unregister-hub-removal"
  let connection_id = "test-unregister-hub-removal:1"
  let outgoing = @async.Queue(kind=Blocking(10))
  register_native_ws_connection(runtime_id, connection_id, outgoing, DropOldest)
  inspect(runtime_is_registered(runtime_id), content="true")
  unregister_native_ws_connection(connection_id)
  inspect(runtime_is_registered(runtime_id), content="false")
}

///|
test "ws_subscribe adds connection to channel" {
  let runtime_id = "test-subscribe"
  let connection_id = "test-subscribe:1"
  let outgoing = @async.Queue(kind=Blocking(10))
  register_native_ws_connection(runtime_id, connection_id, outgoing, DropOldest)
  ws_subscribe(connection_id, "channel-a")
  let channels = snapshot_native_ws_channels(connection_id)
  inspect(channels.length(), content="1")
  inspect(channels[0], content="channel-a")
  inspect(channel_member_count_in_runtime(runtime_id, "channel-a"), content="1")
  cleanup_runtime(runtime_id)
}

///|
test "ws_subscribe is idempotent" {
  let runtime_id = "test-subscribe-idempotent"
  let connection_id = "test-subscribe-idempotent:1"
  let outgoing = @async.Queue(kind=Blocking(10))
  register_native_ws_connection(runtime_id, connection_id, outgoing, DropOldest)
  ws_subscribe(connection_id, "channel-a")
  ws_subscribe(connection_id, "channel-a")
  let channels = snapshot_native_ws_channels(connection_id)
  inspect(channels.length(), content="1")
  inspect(channel_member_count_in_runtime(runtime_id, "channel-a"), content="1")
  cleanup_runtime(runtime_id)
}

///|
test "ws_unsubscribe removes connection from channel" {
  let runtime_id = "test-unsubscribe"
  let connection_id = "test-unsubscribe:1"
  let outgoing = @async.Queue(kind=Blocking(10))
  register_native_ws_connection(runtime_id, connection_id, outgoing, DropOldest)
  ws_subscribe(connection_id, "channel-a")
  ws_unsubscribe(connection_id, "channel-a")
  let channels = snapshot_native_ws_channels(connection_id)
  inspect(channels.length(), content="0")
  inspect(channel_member_count_in_runtime(runtime_id, "channel-a"), content="0")
  cleanup_runtime(runtime_id)
}

///|
test "ws_unsubscribe on non-subscribed channel is safe" {
  let runtime_id = "test-unsubscribe-safe"
  let connection_id = "test-unsubscribe-safe:1"
  let outgoing = @async.Queue(kind=Blocking(10))
  register_native_ws_connection(runtime_id, connection_id, outgoing, DropOldest)
  ws_unsubscribe(connection_id, "never-subscribed")
  let channels = snapshot_native_ws_channels(connection_id)
  inspect(channels.length(), content="0")
  cleanup_runtime(runtime_id)
}

///|
test "decode_native_ws_message decodes text message" {
  match decode_native_ws_message(Text, b"hello") {
    Text(s) => inspect(s, content="hello")
    Binary(_) => fail("expected text message")
  }
}

///|
test "decode_native_ws_message decodes binary message" {
  let data : Bytes = b"binary data"
  match decode_native_ws_message(Binary, data) {
    Binary(b) => inspect(b == data, content="true")
    Text(_) => fail("expected binary message")
  }
}

///|
test "decode_native_ws_message decodes empty text" {
  match decode_native_ws_message(Text, b"") {
    Text(s) => inspect(s, content="")
    Binary(_) => fail("expected text message")
  }
}

///|
test "decode_native_ws_message decodes empty binary" {
  match decode_native_ws_message(Binary, b"") {
    Binary(b) => inspect(b.length(), content="0")
    Text(_) => fail("expected binary message")
  }
}

///|
test "next_native_ws_message_chunk_size returns 1024 when remaining is large" {
  inspect(next_native_ws_message_chunk_size(4096, 0), content="1024")
  inspect(next_native_ws_message_chunk_size(4096, 1024), content="1024")
  inspect(next_native_ws_message_chunk_size(4096, 2048), content="1024")
}

///|
test "next_native_ws_message_chunk_size returns 1024 when remaining is exactly 1024" {
  inspect(next_native_ws_message_chunk_size(2048, 1024), content="1024")
}

///|
test "next_native_ws_message_chunk_size returns remaining plus 1 when under 1024" {
  inspect(next_native_ws_message_chunk_size(1000, 500), content="501")
  inspect(next_native_ws_message_chunk_size(100, 90), content="11")
  inspect(next_native_ws_message_chunk_size(1, 0), content="2")
}

///|
test "native_ws_chunk_exceeds_limit detects exceeding limit" {
  inspect(native_ws_chunk_exceeds_limit(100, 90, 11), content="true")
  inspect(native_ws_chunk_exceeds_limit(100, 90, 10), content="false")
  inspect(native_ws_chunk_exceeds_limit(100, 90, 9), content="false")
  inspect(native_ws_chunk_exceeds_limit(100, 0, 101), content="true")
  inspect(native_ws_chunk_exceeds_limit(100, 0, 100), content="false")
}

///|
test "cleanup_runtime removes all connections for runtime" {
  let runtime_id = "test-cleanup-runtime"
  let outgoing1 = @async.Queue(kind=Blocking(10))
  let outgoing2 = @async.Queue(kind=Blocking(10))
  register_native_ws_connection(
    runtime_id,
    "test-cleanup-runtime:1",
    outgoing1,
    DropOldest,
  )
  register_native_ws_connection(
    runtime_id,
    "test-cleanup-runtime:2",
    outgoing2,
    DropOldest,
  )
  ws_subscribe("test-cleanup-runtime:1", "room")
  ws_subscribe("test-cleanup-runtime:2", "room")
  inspect(channel_member_count_in_runtime(runtime_id, "room"), content="2")
  inspect(connection_is_registered("test-cleanup-runtime:1"), content="true")
  inspect(connection_is_registered("test-cleanup-runtime:2"), content="true")
  cleanup_runtime(runtime_id)
  inspect(connection_is_registered("test-cleanup-runtime:1"), content="false")
  inspect(connection_is_registered("test-cleanup-runtime:2"), content="false")
  inspect(runtime_is_registered(runtime_id), content="false")
}

///|
test "cleanup_runtime is safe on nonexistent runtime" {
  cleanup_runtime("nonexistent-runtime-id")
}

///|
test "multiple connections share same hub channel" {
  let runtime_id = "test-shared-channel"
  let outgoing1 = @async.Queue(kind=Blocking(10))
  let outgoing2 = @async.Queue(kind=Blocking(10))
  register_native_ws_connection(
    runtime_id,
    "test-shared-channel:1",
    outgoing1,
    DropOldest,
  )
  register_native_ws_connection(
    runtime_id,
    "test-shared-channel:2",
    outgoing2,
    DropOldest,
  )
  ws_subscribe("test-shared-channel:1", "shared-room")
  ws_subscribe("test-shared-channel:2", "shared-room")
  inspect(
    channel_member_count_in_runtime(runtime_id, "shared-room"),
    content="2",
  )
  ws_unsubscribe("test-shared-channel:1", "shared-room")
  inspect(
    channel_member_count_in_runtime(runtime_id, "shared-room"),
    content="1",
  )
  ws_unsubscribe("test-shared-channel:2", "shared-room")
  inspect(
    channel_member_count_in_runtime(runtime_id, "shared-room"),
    content="0",
  )
  cleanup_runtime(runtime_id)
}
