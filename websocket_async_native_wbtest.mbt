///|
suberror WebSocketLifecycleServerNotReady

///|
suberror WebSocketLifecycleSocketBindUnavailable

///|
async fn allocate_websocket_lifecycle_server() -> @http.Server {
  let addr = @socket.Addr::parse("127.0.0.1:0") catch {
    _ => raise WebSocketLifecycleSocketBindUnavailable
  }
  Server(addr, reuse_addr=true) catch {
    @os_error.OSError(errno, ..) if errno == 1 =>
      raise WebSocketLifecycleSocketBindUnavailable
    @os_error.OSError(_) as err if err.is_EACCES() =>
      raise WebSocketLifecycleSocketBindUnavailable
    err => fail("unexpected bind check failure: \{err}")
  }
}

///|
fn websocket_lifecycle_url(port : Int, path : String) -> String {
  "http://127.0.0.1:\{port}\{path}"
}

///|
async fn wait_until_websocket_lifecycle_ready(port : Int) -> Unit {
  @async.retry(FixedDelay(20), max_retry=50, () => {
    let (response, _body) = @http.get(
      websocket_lifecycle_url(port, "/__ws_lifecycle_ready"),
    )
    guard response.code == 200 else { raise WebSocketLifecycleServerNotReady }
  })
}

// Helpers below proxy to the public introspection API in
// bobzhang/crescent/websocket. Pure-internal whitebox tests (drop-policy
// enqueue, hub primitives, decode/chunk helpers) live in
// websocket/runtime_wbtest.mbt where they have direct access to private
// state.

///|
fn native_ws_hub_count() -> Int {
  @ws.registered_runtime_count()
}

///|
fn native_ws_connection_hub_count() -> Int {
  @ws.registered_connection_count()
}

///|
fn native_ws_channel_member_count(channel : String) -> Int {
  @ws.channel_member_count(channel)
}

///|
fn native_ws_runtime_ids_for_app(app : App) -> Array[String] {
  app.ws_runtime_ids()
}

///|
fn native_ws_channel_member_count_in_runtime(
  runtime_id : String,
  channel : String,
) -> Int {
  @ws.channel_member_count_in_runtime(runtime_id, channel)
}

///|
fn native_ws_connection_exists(connection_id : String) -> Bool {
  @ws.connection_is_registered(connection_id)
}

// Internal-helper unit tests (drop-policy enqueue, decode helpers, hub
// register/cleanup primitives) moved to websocket/runtime_wbtest.mbt.

///|
async test "serve_on clears websocket runtime state on cancellation" {
  let initial_hub_count = native_ws_hub_count()
  let initial_connection_hub_count = native_ws_connection_hub_count()

  let app = App()
  app.get("/__ws_lifecycle_ready", _ => "ready")
  app.ws("/hub", event => {
    match event {
      Open(peer) => peer.subscribe("room")
      Message(peer, Text("publish")) => peer.publish("room", "fanout")
      _ => ()
    }
  })

  @async.with_task_group(group => {
    let server = allocate_websocket_lifecycle_server()
    let port = server.addr.port()
    let task = group.spawn(no_wait=true, () => app.serve_on(server))
    wait_until_websocket_lifecycle_ready(port)

    let client = @websocket.connect("ws://127.0.0.1:\{port}/hub")
    defer client.close()

    client.send_text("publish")
    debug_inspect(
      client.recv().read_all().text(),
      content=(
        #|"fanout"
      ),
    )

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_hub_count() > initial_hub_count &&
        native_ws_connection_hub_count() > initial_connection_hub_count else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    task.cancel()
    assert_eq(
      @async.with_timeout_opt(200, () => ignore(task.wait()) catch { _ => () }),
      Some(()),
    )

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_hub_count() == initial_hub_count &&
        native_ws_connection_hub_count() == initial_connection_hub_count else {
        raise WebSocketLifecycleServerNotReady
      }
    })
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on_until clears websocket runtime state on shutdown signal" {
  let initial_hub_count = native_ws_hub_count()
  let initial_connection_hub_count = native_ws_connection_hub_count()

  let app = App()
  app.get("/__ws_lifecycle_ready", _ => "ready")
  app.ws("/hub", event => {
    match event {
      Open(peer) => peer.subscribe("room")
      Message(peer, Text("publish")) => peer.publish("room", "fanout")
      _ => ()
    }
  })

  @async.with_task_group(group => {
    let server = allocate_websocket_lifecycle_server()
    let port = server.addr.port()
    let shutdown = @async.Queue(kind=Blocking(0))
    let task = group.spawn(no_wait=true, () => app.serve_on(server, shutdown~))
    wait_until_websocket_lifecycle_ready(port)

    let client = @websocket.connect("ws://127.0.0.1:\{port}/hub")
    defer client.close()

    client.send_text("publish")
    debug_inspect(
      client.recv().read_all().text(),
      content=(
        #|"fanout"
      ),
    )

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_hub_count() > initial_hub_count &&
        native_ws_connection_hub_count() > initial_connection_hub_count else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    shutdown.put(())
    match @async.with_timeout_opt(200, () => task.wait()) {
      Some(_) => ()
      None =>
        fail(
          "timed out waiting for websocket runtime to stop after shutdown signal",
        )
    }

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_hub_count() == initial_hub_count &&
        native_ws_connection_hub_count() == initial_connection_hub_count else {
        raise WebSocketLifecycleServerNotReady
      }
    })
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on removes websocket channel subscriptions on close" {
  @async.with_task_group(group => {
    let server = allocate_websocket_lifecycle_server()
    let port = server.addr.port()
    let channel = "room-close-cleanup-\{port}"
    let app = App()
    app.get("/__ws_lifecycle_ready", _ => "ready")
    app.ws("/hub", event => {
      match event {
        Open(peer) => peer.subscribe(channel)
        Message(peer, Text("publish")) => peer.publish(channel, "fanout")
        _ => ()
      }
    })
    let task = group.spawn(no_wait=true, () => app.serve_on(server))
    wait_until_websocket_lifecycle_ready(port)

    let client1 = @websocket.connect("ws://127.0.0.1:\{port}/hub")
    defer client1.close()
    let client2 = @websocket.connect("ws://127.0.0.1:\{port}/hub")
    defer client2.close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_channel_member_count(channel) == 2 else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    client1.send_close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_channel_member_count(channel) == 1 else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    client2.send_text("publish")
    debug_inspect(
      client2.recv().read_all().text(),
      content=(
        #|"fanout"
      ),
    )

    task.cancel()
    assert_eq(
      @async.with_timeout_opt(200, () => ignore(task.wait()) catch { _ => () }),
      Some(()),
    )

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_channel_member_count(channel) == 0 else {
        raise WebSocketLifecycleServerNotReady
      }
    })
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on makes closed websocket peers inert after unregister" {
  let closed_peer : Ref[WebSocketPeer?] = Ref(None)
  @async.with_task_group(group => {
    let server = allocate_websocket_lifecycle_server()
    let port = server.addr.port()
    let channel = "room-stale-peer-\{port}"
    let app = App()
    app.get("/__ws_lifecycle_ready", _ => "ready")
    app.ws("/hub", event => {
      match event {
        Open(peer) => peer.subscribe(channel)
        Message(peer, Text("publish")) => peer.publish(channel, "fanout")
        Message(_, Text("poke-stale")) =>
          match closed_peer.val {
            Some(peer) => {
              peer.text("ghost-direct")
              peer.publish(channel, "ghost-publish")
            }
            None => ()
          }
        Close(peer) => closed_peer.val = Some(peer)
        _ => ()
      }
    })
    let task = group.spawn(no_wait=true, () => app.serve_on(server))
    wait_until_websocket_lifecycle_ready(port)

    let client1 = @websocket.connect("ws://127.0.0.1:\{port}/hub")
    defer client1.close()
    let client2 = @websocket.connect("ws://127.0.0.1:\{port}/hub")
    defer client2.close()

    client1.send_text("publish")
    debug_inspect(
      client1.recv().read_all().text(),
      content=(
        #|"fanout"
      ),
    )
    debug_inspect(
      client2.recv().read_all().text(),
      content=(
        #|"fanout"
      ),
    )

    client1.send_close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      match closed_peer.val {
        Some(peer) => {
          guard !native_ws_connection_exists(peer.connection_id()) &&
            native_ws_channel_member_count(channel) == 1 else {
            raise WebSocketLifecycleServerNotReady
          }
        }
        None => raise WebSocketLifecycleServerNotReady
      }
    })

    client2.send_text("poke-stale")
    debug_inspect(
      @async.with_timeout_opt(100, () => client2.recv().read_all().text()),
      content="None",
    )

    client2.send_text("publish")
    debug_inspect(
      client2.recv().read_all().text(),
      content=(
        #|"fanout"
      ),
    )

    task.cancel()
    assert_eq(
      @async.with_timeout_opt(200, () => ignore(task.wait()) catch { _ => () }),
      Some(()),
    )

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_channel_member_count(channel) == 0 else {
        raise WebSocketLifecycleServerNotReady
      }
    })
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on cleans up channel membership after client close" {
  // The runtime invariant that the outgoing queue is closed BEFORE the
  // user's Close handler runs is verified directly in the websocket
  // package's whitebox test ("outgoing queue is closed before Close
  // handler fires"). Here we only check the integration-level
  // observable: after a client closes, the server-side hub state is
  // cleaned up and the remaining client still works.
  let close_connection_id : Ref[String?] = Ref(None)
  let close_channel_members : Ref[Int?] = Ref(None)
  @async.with_task_group(group => {
    let server = allocate_websocket_lifecycle_server()
    let port = server.addr.port()
    let channel = "room-close-order-\{port}"
    let app = App()
    app.get("/__ws_lifecycle_ready", _ => "ready")
    app.ws("/hub", event => {
      match event {
        Open(peer) => peer.subscribe(channel)
        Message(peer, Text("publish")) => peer.publish(channel, "fanout")
        Close(peer) => {
          close_connection_id.val = Some(peer.connection_id())
          close_channel_members.val = Some(
            native_ws_channel_member_count(channel),
          )
        }
        _ => ()
      }
    })
    let task = group.spawn(no_wait=true, () => app.serve_on(server))
    wait_until_websocket_lifecycle_ready(port)

    let client1 = @websocket.connect("ws://127.0.0.1:\{port}/hub")
    defer client1.close()
    let client2 = @websocket.connect("ws://127.0.0.1:\{port}/hub")
    defer client2.close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_channel_member_count(channel) == 2 else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    client1.send_close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard close_connection_id.val is Some(_) &&
        close_channel_members.val is Some(_) else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    debug_inspect(close_channel_members.val, content="Some(2)")

    @async.retry(FixedDelay(20), max_retry=50, () => {
      match close_connection_id.val {
        Some(connection_id) => {
          guard !native_ws_connection_exists(connection_id) &&
            native_ws_channel_member_count(channel) == 1 else {
            raise WebSocketLifecycleServerNotReady
          }
        }
        None => raise WebSocketLifecycleServerNotReady
      }
    })

    client2.send_text("publish")
    debug_inspect(
      client2.recv().read_all().text(),
      content=(
        #|"fanout"
      ),
    )

    task.cancel()
    assert_eq(
      @async.with_timeout_opt(200, () => ignore(task.wait()) catch { _ => () }),
      Some(()),
    )

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_channel_member_count(channel) == 0 else {
        raise WebSocketLifecycleServerNotReady
      }
    })
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on cleans up subscriptions added during close handler" {
  let close_connection_id : Ref[String?] = Ref(None)
  let close_primary_members : Ref[Int?] = Ref(None)
  let close_late_members : Ref[Int?] = Ref(None)
  @async.with_task_group(group => {
    let server = allocate_websocket_lifecycle_server()
    let port = server.addr.port()
    let primary_channel = "room-close-primary-\{port}"
    let late_channel = "room-close-late-\{port}"
    let app = App()
    app.get("/__ws_lifecycle_ready", _ => "ready")
    app.ws("/hub", event => {
      match event {
        Open(peer) => peer.subscribe(primary_channel)
        Close(peer) => {
          close_connection_id.val = Some(peer.connection_id())
          peer.subscribe(late_channel)
          close_primary_members.val = Some(
            native_ws_channel_member_count(primary_channel),
          )
          close_late_members.val = Some(
            native_ws_channel_member_count(late_channel),
          )
        }
        _ => ()
      }
    })
    let task = group.spawn(no_wait=true, () => app.serve_on(server))
    wait_until_websocket_lifecycle_ready(port)

    let client = @websocket.connect("ws://127.0.0.1:\{port}/hub")
    defer client.close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_channel_member_count(primary_channel) == 1 else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    client.send_close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard close_connection_id.val is Some(_) &&
        close_primary_members.val is Some(_) &&
        close_late_members.val is Some(_) else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    debug_inspect(close_primary_members.val, content="Some(1)")
    debug_inspect(close_late_members.val, content="Some(1)")

    @async.retry(FixedDelay(20), max_retry=50, () => {
      match close_connection_id.val {
        Some(connection_id) => {
          guard !native_ws_connection_exists(connection_id) &&
            native_ws_channel_member_count(primary_channel) == 0 &&
            native_ws_channel_member_count(late_channel) == 0 else {
            raise WebSocketLifecycleServerNotReady
          }
        }
        None => raise WebSocketLifecycleServerNotReady
      }
    })

    task.cancel()
    assert_eq(
      @async.with_timeout_opt(200, () => ignore(task.wait()) catch { _ => () }),
      Some(()),
    )
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on handles unsubscribe then subscribe mutations during close handler" {
  let close_connection_id : Ref[String?] = Ref(None)
  let close_primary_members : Ref[Int?] = Ref(None)
  let close_late_members : Ref[Int?] = Ref(None)
  @async.with_task_group(group => {
    let server = allocate_websocket_lifecycle_server()
    let port = server.addr.port()
    let primary_channel = "room-close-swap-primary-\{port}"
    let late_channel = "room-close-swap-late-\{port}"
    let app = App()
    app.get("/__ws_lifecycle_ready", _ => "ready")
    app.ws("/hub", event => {
      match event {
        Open(peer) => peer.subscribe(primary_channel)
        Close(peer) => {
          close_connection_id.val = Some(peer.connection_id())
          peer.unsubscribe(primary_channel)
          peer.subscribe(late_channel)
          close_primary_members.val = Some(
            native_ws_channel_member_count(primary_channel),
          )
          close_late_members.val = Some(
            native_ws_channel_member_count(late_channel),
          )
        }
        _ => ()
      }
    })
    let task = group.spawn(no_wait=true, () => app.serve_on(server))
    wait_until_websocket_lifecycle_ready(port)

    let client = @websocket.connect("ws://127.0.0.1:\{port}/hub")
    defer client.close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_channel_member_count(primary_channel) == 1 else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    client.send_close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard close_connection_id.val is Some(_) &&
        close_primary_members.val is Some(_) &&
        close_late_members.val is Some(_) else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    debug_inspect(close_primary_members.val, content="Some(0)")
    debug_inspect(close_late_members.val, content="Some(1)")

    @async.retry(FixedDelay(20), max_retry=50, () => {
      match close_connection_id.val {
        Some(connection_id) => {
          guard !native_ws_connection_exists(connection_id) &&
            native_ws_channel_member_count(primary_channel) == 0 &&
            native_ws_channel_member_count(late_channel) == 0 else {
            raise WebSocketLifecycleServerNotReady
          }
        }
        None => raise WebSocketLifecycleServerNotReady
      }
    })

    task.cancel()
    assert_eq(
      @async.with_timeout_opt(200, () => ignore(task.wait()) catch { _ => () }),
      Some(()),
    )
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on keeps close-handler mutations isolated across reused app runtimes" {
  let close_runtime_id : Ref[String?] = Ref(None)
  let close_room_members : Ref[Int?] = Ref(None)
  let close_late_members : Ref[Int?] = Ref(None)
  let close_late_runtime_count : Ref[Int?] = Ref(None)
  let app = App()
  app.get("/__ws_lifecycle_ready", _ => "ready")
  app.ws("/hub", event => {
    match event {
      Open(peer) => peer.subscribe("room")
      Message(peer, Text("publish")) => peer.publish("room", "fanout")
      Close(peer) => {
        close_runtime_id.val = @ws.runtime_id_for_connection(
          peer.connection_id(),
        )
        peer.subscribe("late")
        let runtime_ids = native_ws_runtime_ids_for_app(app)
        let mut room_members = 0
        let mut late_members = 0
        let mut late_runtime_count = 0
        for runtime_id in runtime_ids {
          let room_count = native_ws_channel_member_count_in_runtime(
            runtime_id, "room",
          )
          let late_count = native_ws_channel_member_count_in_runtime(
            runtime_id, "late",
          )
          room_members += room_count
          late_members += late_count
          if late_count > 0 {
            late_runtime_count += 1
          }
        }
        close_room_members.val = Some(room_members)
        close_late_members.val = Some(late_members)
        close_late_runtime_count.val = Some(late_runtime_count)
      }
      _ => ()
    }
  })

  @async.with_task_group(group => {
    let server1 = allocate_websocket_lifecycle_server()
    let server2 = allocate_websocket_lifecycle_server()
    let port1 = server1.addr.port()
    let port2 = server2.addr.port()
    let task1 = group.spawn(no_wait=true, () => app.serve_on(server1))
    let task2 = group.spawn(no_wait=true, () => app.serve_on(server2))
    wait_until_websocket_lifecycle_ready(port1)
    wait_until_websocket_lifecycle_ready(port2)

    let client1 = @websocket.connect("ws://127.0.0.1:\{port1}/hub")
    defer client1.close()
    let client2 = @websocket.connect("ws://127.0.0.1:\{port2}/hub")
    defer client2.close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      let runtime_ids = native_ws_runtime_ids_for_app(app)
      guard runtime_ids.length() == 2 else {
        raise WebSocketLifecycleServerNotReady
      }
      let mut room_members = 0
      for runtime_id in runtime_ids {
        room_members += native_ws_channel_member_count_in_runtime(
          runtime_id, "room",
        )
      }
      guard room_members == 2 else { raise WebSocketLifecycleServerNotReady }
    })

    client1.send_close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard close_runtime_id.val is Some(_) &&
        close_room_members.val is Some(_) &&
        close_late_members.val is Some(_) &&
        close_late_runtime_count.val is Some(_) else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    debug_inspect(close_room_members.val, content="Some(2)")
    debug_inspect(close_late_members.val, content="Some(1)")
    debug_inspect(close_late_runtime_count.val, content="Some(1)")

    @async.retry(FixedDelay(20), max_retry=50, () => {
      let runtime_ids = native_ws_runtime_ids_for_app(app)
      guard runtime_ids.length() == 1 else {
        raise WebSocketLifecycleServerNotReady
      }
      let surviving_runtime_id = runtime_ids[0]
      guard native_ws_channel_member_count_in_runtime(
          surviving_runtime_id, "room",
        ) ==
        1 &&
        native_ws_channel_member_count_in_runtime(surviving_runtime_id, "late") ==
        0 else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    client2.send_text("publish")
    debug_inspect(
      client2.recv().read_all().text(),
      content=(
        #|"fanout"
      ),
    )

    task1.cancel()
    task2.cancel()
    assert_eq(
      @async.with_timeout_opt(200, () => ignore(task1.wait()) catch { _ => () }),
      Some(()),
    )
    assert_eq(
      @async.with_timeout_opt(200, () => ignore(task2.wait()) catch { _ => () }),
      Some(()),
    )

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_runtime_ids_for_app(app).is_empty() else {
        raise WebSocketLifecycleServerNotReady
      }
    })
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on cancellation stays isolated across reused app runtimes" {
  let app = App()
  app.get("/__ws_lifecycle_ready", _ => "ready")
  app.ws("/hub", event => {
    match event {
      Open(peer) => peer.subscribe("room")
      Message(peer, Text("publish")) => peer.publish("room", "fanout")
      _ => ()
    }
  })

  @async.with_task_group(group => {
    let server1 = allocate_websocket_lifecycle_server()
    let server2 = allocate_websocket_lifecycle_server()
    let port1 = server1.addr.port()
    let port2 = server2.addr.port()
    let task1 = group.spawn(no_wait=true, () => app.serve_on(server1))
    let task2 = group.spawn(no_wait=true, () => app.serve_on(server2))
    wait_until_websocket_lifecycle_ready(port1)
    wait_until_websocket_lifecycle_ready(port2)

    let client1 = @websocket.connect("ws://127.0.0.1:\{port1}/hub")
    defer client1.close()
    let client2 = @websocket.connect("ws://127.0.0.1:\{port2}/hub")
    defer client2.close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      let runtime_ids = native_ws_runtime_ids_for_app(app)
      guard runtime_ids.length() == 2 else {
        raise WebSocketLifecycleServerNotReady
      }
      let mut room_members = 0
      for runtime_id in runtime_ids {
        room_members += native_ws_channel_member_count_in_runtime(
          runtime_id, "room",
        )
      }
      guard room_members == 2 else { raise WebSocketLifecycleServerNotReady }
    })

    task1.cancel()
    assert_eq(
      @async.with_timeout_opt(200, () => ignore(task1.wait()) catch { _ => () }),
      Some(()),
    )

    @async.retry(FixedDelay(20), max_retry=50, () => {
      let runtime_ids = native_ws_runtime_ids_for_app(app)
      guard runtime_ids.length() == 1 else {
        raise WebSocketLifecycleServerNotReady
      }
      let surviving_runtime_id = runtime_ids[0]
      guard native_ws_channel_member_count_in_runtime(
          surviving_runtime_id, "room",
        ) ==
        1 else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    client2.send_text("publish")
    debug_inspect(
      client2.recv().read_all().text(),
      content=(
        #|"fanout"
      ),
    )

    task2.cancel()
    assert_eq(
      @async.with_timeout_opt(200, () => ignore(task2.wait()) catch { _ => () }),
      Some(()),
    )

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_runtime_ids_for_app(app).is_empty() else {
        raise WebSocketLifecycleServerNotReady
      }
    })
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on_until shutdown stays isolated across reused app runtimes" {
  let app = App()
  app.get("/__ws_lifecycle_ready", _ => "ready")
  app.ws("/hub", event => {
    match event {
      Open(peer) => peer.subscribe("room")
      Message(peer, Text("publish")) => peer.publish("room", "fanout")
      _ => ()
    }
  })

  @async.with_task_group(group => {
    let server1 = allocate_websocket_lifecycle_server()
    let server2 = allocate_websocket_lifecycle_server()
    let port1 = server1.addr.port()
    let port2 = server2.addr.port()
    let shutdown1 = @async.Queue(kind=Unbounded)
    let shutdown2 = @async.Queue(kind=Unbounded)
    let task1 = group.spawn(no_wait=true, () => {
      app.serve_on(server1, shutdown=shutdown1)
    })
    let task2 = group.spawn(no_wait=true, () => {
      app.serve_on(server2, shutdown=shutdown2)
    })
    wait_until_websocket_lifecycle_ready(port1)
    wait_until_websocket_lifecycle_ready(port2)

    let client1 = @websocket.connect("ws://127.0.0.1:\{port1}/hub")
    defer client1.close()
    let client2 = @websocket.connect("ws://127.0.0.1:\{port2}/hub")
    defer client2.close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      let runtime_ids = native_ws_runtime_ids_for_app(app)
      guard runtime_ids.length() == 2 else {
        raise WebSocketLifecycleServerNotReady
      }
      let mut room_members = 0
      for runtime_id in runtime_ids {
        room_members += native_ws_channel_member_count_in_runtime(
          runtime_id, "room",
        )
      }
      guard room_members == 2 else { raise WebSocketLifecycleServerNotReady }
    })

    shutdown1.put(())
    match @async.with_timeout_opt(200, () => task1.wait()) {
      Some(_) => ()
      None =>
        fail(
          "timed out waiting for first reused-app shutdown signal to stop server",
        )
    }

    @async.retry(FixedDelay(20), max_retry=50, () => {
      let runtime_ids = native_ws_runtime_ids_for_app(app)
      guard runtime_ids.length() == 1 else {
        raise WebSocketLifecycleServerNotReady
      }
      let surviving_runtime_id = runtime_ids[0]
      guard native_ws_channel_member_count_in_runtime(
          surviving_runtime_id, "room",
        ) ==
        1 else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    client2.send_text("publish")
    debug_inspect(
      client2.recv().read_all().text(),
      content=(
        #|"fanout"
      ),
    )

    shutdown2.put(())
    match @async.with_timeout_opt(200, () => task2.wait()) {
      Some(_) => ()
      None =>
        fail(
          "timed out waiting for second reused-app shutdown signal to stop server",
        )
    }

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_runtime_ids_for_app(app).is_empty() else {
        raise WebSocketLifecycleServerNotReady
      }
    })
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on_until queue close clears reused app websocket runtimes" {
  let app = App()
  app.get("/__ws_lifecycle_ready", _ => "ready")
  app.ws("/hub", event => {
    match event {
      Open(peer) => peer.subscribe("room")
      Message(peer, Text("publish")) => peer.publish("room", "fanout")
      _ => ()
    }
  })

  @async.with_task_group(group => {
    let server1 = allocate_websocket_lifecycle_server()
    let server2 = allocate_websocket_lifecycle_server()
    let port1 = server1.addr.port()
    let port2 = server2.addr.port()
    let shutdown = @async.Queue(kind=Blocking(0))
    let task1 = group.spawn(no_wait=true, () => app.serve_on(server1, shutdown~))
    let task2 = group.spawn(no_wait=true, () => app.serve_on(server2, shutdown~))
    wait_until_websocket_lifecycle_ready(port1)
    wait_until_websocket_lifecycle_ready(port2)

    let client1 = @websocket.connect("ws://127.0.0.1:\{port1}/hub")
    defer client1.close()
    let client2 = @websocket.connect("ws://127.0.0.1:\{port2}/hub")
    defer client2.close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      let runtime_ids = native_ws_runtime_ids_for_app(app)
      guard runtime_ids.length() == 2 else {
        raise WebSocketLifecycleServerNotReady
      }
      let mut room_members = 0
      for runtime_id in runtime_ids {
        room_members += native_ws_channel_member_count_in_runtime(
          runtime_id, "room",
        )
      }
      guard room_members == 2 else { raise WebSocketLifecycleServerNotReady }
    })

    shutdown.close()

    match @async.with_timeout_opt(200, () => task1.wait()) {
      Some(_) => ()
      None =>
        fail(
          "timed out waiting for first reused-app queue-close shutdown to stop server",
        )
    }
    match @async.with_timeout_opt(200, () => task2.wait()) {
      Some(_) => ()
      None =>
        fail(
          "timed out waiting for second reused-app queue-close shutdown to stop server",
        )
    }

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_runtime_ids_for_app(app).is_empty() else {
        raise WebSocketLifecycleServerNotReady
      }
    })
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on_until queue close clears remaining reused runtime after cancellation" {
  let app = App()
  app.get("/__ws_lifecycle_ready", _ => "ready")
  app.ws("/hub", event => {
    match event {
      Open(peer) => peer.subscribe("room")
      Message(peer, Text("publish")) => peer.publish("room", "fanout")
      _ => ()
    }
  })

  @async.with_task_group(group => {
    let server1 = allocate_websocket_lifecycle_server()
    let server2 = allocate_websocket_lifecycle_server()
    let port1 = server1.addr.port()
    let port2 = server2.addr.port()
    let shutdown = @async.Queue(kind=Unbounded)
    let task1 = group.spawn(no_wait=true, () => app.serve_on(server1, shutdown~))
    let task2 = group.spawn(no_wait=true, () => app.serve_on(server2, shutdown~))
    wait_until_websocket_lifecycle_ready(port1)
    wait_until_websocket_lifecycle_ready(port2)

    let client1 = @websocket.connect("ws://127.0.0.1:\{port1}/hub")
    defer client1.close()
    let client2 = @websocket.connect("ws://127.0.0.1:\{port2}/hub")
    defer client2.close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      let runtime_ids = native_ws_runtime_ids_for_app(app)
      guard runtime_ids.length() == 2 else {
        raise WebSocketLifecycleServerNotReady
      }
      let mut room_members = 0
      for runtime_id in runtime_ids {
        room_members += native_ws_channel_member_count_in_runtime(
          runtime_id, "room",
        )
      }
      guard room_members == 2 else { raise WebSocketLifecycleServerNotReady }
    })

    task1.cancel()
    assert_eq(
      @async.with_timeout_opt(200, () => ignore(task1.wait()) catch { _ => () }),
      Some(()),
    )

    @async.retry(FixedDelay(20), max_retry=50, () => {
      let runtime_ids = native_ws_runtime_ids_for_app(app)
      guard runtime_ids.length() == 1 else {
        raise WebSocketLifecycleServerNotReady
      }
      let surviving_runtime_id = runtime_ids[0]
      guard native_ws_channel_member_count_in_runtime(
          surviving_runtime_id, "room",
        ) ==
        1 else {
        raise WebSocketLifecycleServerNotReady
      }
    })

    client2.send_text("publish")
    debug_inspect(
      client2.recv().read_all().text(),
      content=(
        #|"fanout"
      ),
    )

    shutdown.close()

    match @async.with_timeout_opt(200, () => task2.wait()) {
      Some(_) => ()
      None =>
        fail(
          "timed out waiting for surviving reused-app queue-close shutdown to stop server",
        )
    }

    @async.retry(FixedDelay(20), max_retry=50, () => {
      guard native_ws_runtime_ids_for_app(app).is_empty() else {
        raise WebSocketLifecycleServerNotReady
      }
    })
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on_until shutdown signal wakes one reused runtime" {
  let app = App()
  app.get("/__ws_lifecycle_ready", _ => "ready")
  app.ws("/hub", event => {
    match event {
      Open(peer) => peer.subscribe("room")
      Message(peer, Text("publish")) => peer.publish("room", "fanout")
      _ => ()
    }
  })

  @async.with_task_group(group => {
    let server1 = allocate_websocket_lifecycle_server()
    let server2 = allocate_websocket_lifecycle_server()
    let port1 = server1.addr.port()
    let port2 = server2.addr.port()
    let shutdown = @async.Queue(kind=Blocking(0))
    let task1 = group.spawn(no_wait=true, () => app.serve_on(server1, shutdown~))
    let task2 = group.spawn(no_wait=true, () => app.serve_on(server2, shutdown~))
    wait_until_websocket_lifecycle_ready(port1)
    wait_until_websocket_lifecycle_ready(port2)

    let client1 = @websocket.connect("ws://127.0.0.1:\{port1}/hub")
    defer client1.close()
    let client2 = @websocket.connect("ws://127.0.0.1:\{port2}/hub")
    defer client2.close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      let runtime_ids = native_ws_runtime_ids_for_app(app)
      guard runtime_ids.length() == 2 else {
        raise WebSocketLifecycleServerNotReady
      }
      let mut room_members = 0
      for runtime_id in runtime_ids {
        room_members += native_ws_channel_member_count_in_runtime(
          runtime_id, "room",
        )
      }
      guard room_members == 2 else { raise WebSocketLifecycleServerNotReady }
    })

    shutdown.put(())
    let client1_after = @async.with_timeout_opt(300, () => {
      try client1.recv().read_all().text() catch {
        err => Err(err)
      } noraise {
        text => Ok(text)
      }
    })
    let client2_after = @async.with_timeout_opt(300, () => {
      try client2.recv().read_all().text() catch {
        err => Err(err)
      } noraise {
        text => Ok(text)
      }
    })

    match client1_after {
      Some(Err(@websocket.ConnectionClosed(GoingAway, Some(reason)))) => {
        debug_inspect(
          reason,
          content=(
            #|"websocket server shutdown"
          ),
        )
        match client2_after {
          None => ()
          Some(Err(@websocket.ConnectionClosed(code, why))) =>
            fail(
              "expected only one reused runtime to stop after shutdown signal, but both websocket clients closed: \{@debug.to_string(code)} / \{@debug.to_string(why)}",
            )
          Some(Err(err)) => raise err
          Some(Ok(text)) =>
            fail(
              "expected sibling reused websocket runtime to stay alive after shutdown signal, got text: \{text}",
            )
        }
        match @async.with_timeout_opt(200, () => task1.wait()) {
          Some(_) => ()
          None => fail("timed out waiting for signaled reused runtime to stop")
        }
        @async.retry(FixedDelay(20), max_retry=50, () => {
          let runtime_ids = native_ws_runtime_ids_for_app(app)
          guard runtime_ids.length() == 1 else {
            raise WebSocketLifecycleServerNotReady
          }
          let surviving_runtime_id = runtime_ids[0]
          guard native_ws_channel_member_count_in_runtime(
              surviving_runtime_id, "room",
            ) ==
            1 else {
            raise WebSocketLifecycleServerNotReady
          }
        })
        match @async.with_timeout_opt(100, () => task2.wait()) {
          Some(_) =>
            fail(
              "expected sibling reused runtime to stay alive after one shutdown signal",
            )
          None => ()
        }
        client2.send_text("publish")
        debug_inspect(
          client2.recv().read_all().text(),
          content=(
            #|"fanout"
          ),
        )
        try shutdown.try_put(()) catch {
          err =>
            fail(
              "expected second shutdown signal delivery to the surviving reused runtime to succeed: \{err}",
            )
        } noraise {
          delivered =>
            if !delivered {
              fail(
                "expected surviving reused runtime to remain blocked on the shutdown queue after one shutdown signal",
              )
            }
        }
        match @async.with_timeout_opt(200, () => task2.wait()) {
          Some(_) => ()
          None =>
            fail(
              "timed out waiting for the surviving reused runtime to stop after second shutdown signal",
            )
        }
        @async.retry(FixedDelay(20), max_retry=50, () => {
          guard native_ws_runtime_ids_for_app(app).is_empty() else {
            raise WebSocketLifecycleServerNotReady
          }
        })
      }
      Some(Err(@websocket.ConnectionClosed(code, reason))) =>
        fail(
          "expected stopped reused websocket client to observe going-away close after shutdown signal, got \{@debug.to_string(code)} / \{@debug.to_string(reason)}",
        )
      Some(Err(err)) => raise err
      Some(Ok(text)) =>
        fail(
          "expected stopped reused websocket client to observe shutdown close, got text: \{text}",
        )
      None =>
        match client2_after {
          Some(Err(@websocket.ConnectionClosed(GoingAway, Some(reason)))) => {
            debug_inspect(reason, content="websocket server shutdown")
            match @async.with_timeout_opt(200, () => task2.wait()) {
              Some(_) => ()
              None =>
                fail("timed out waiting for signaled reused runtime to stop")
            }
            @async.retry(FixedDelay(20), max_retry=50, () => {
              let runtime_ids = native_ws_runtime_ids_for_app(app)
              guard runtime_ids.length() == 1 else {
                raise WebSocketLifecycleServerNotReady
              }
              let surviving_runtime_id = runtime_ids[0]
              guard native_ws_channel_member_count_in_runtime(
                  surviving_runtime_id, "room",
                ) ==
                1 else {
                raise WebSocketLifecycleServerNotReady
              }
            })
            match @async.with_timeout_opt(100, () => task1.wait()) {
              Some(_) =>
                fail(
                  "expected sibling reused runtime to stay alive after one shutdown signal",
                )
              None => ()
            }
            client1.send_text("publish")
            debug_inspect(client1.recv().read_all().text(), content="fanout")
            try shutdown.try_put(()) catch {
              err =>
                fail(
                  "expected second shutdown signal delivery to the surviving reused runtime to succeed: \{err}",
                )
            } noraise {
              delivered =>
                if !delivered {
                  fail(
                    "expected surviving reused runtime to remain blocked on the shutdown queue after one shutdown signal",
                  )
                }
            }
            match @async.with_timeout_opt(200, () => task1.wait()) {
              Some(_) => ()
              None =>
                fail(
                  "timed out waiting for the surviving reused runtime to stop after second shutdown signal",
                )
            }
            @async.retry(FixedDelay(20), max_retry=50, () => {
              guard native_ws_runtime_ids_for_app(app).is_empty() else {
                raise WebSocketLifecycleServerNotReady
              }
            })
          }
          Some(Err(@websocket.ConnectionClosed(code, reason))) =>
            fail(
              "expected exactly one reused websocket runtime to stop after shutdown signal, but got unexpected second close: \{@debug.to_string(code)} / \{@debug.to_string(reason)}",
            )
          Some(Err(err)) => raise err
          Some(Ok(text)) =>
            fail(
              "expected a reused websocket runtime to stop after shutdown signal, got text: \{text}",
            )
          None =>
            fail(
              "expected exactly one reused websocket runtime to stop after shutdown signal",
            )
        }
    }
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

///|
async test "serve_on_until queue close clears surviving reused runtime after shutdown signal" {
  let app = App()
  app.get("/__ws_lifecycle_ready", _ => "ready")
  app.ws("/hub", event => {
    match event {
      Open(peer) => peer.subscribe("room")
      Message(peer, Text("publish")) => peer.publish("room", "fanout")
      _ => ()
    }
  })

  @async.with_task_group(group => {
    let server1 = allocate_websocket_lifecycle_server()
    let server2 = allocate_websocket_lifecycle_server()
    let port1 = server1.addr.port()
    let port2 = server2.addr.port()
    let shutdown = @async.Queue(kind=Blocking(0))
    let task1 = group.spawn(no_wait=true, () => app.serve_on(server1, shutdown~))
    let task2 = group.spawn(no_wait=true, () => app.serve_on(server2, shutdown~))
    wait_until_websocket_lifecycle_ready(port1)
    wait_until_websocket_lifecycle_ready(port2)

    let client1 = @websocket.connect("ws://127.0.0.1:\{port1}/hub")
    defer client1.close()
    let client2 = @websocket.connect("ws://127.0.0.1:\{port2}/hub")
    defer client2.close()

    @async.retry(FixedDelay(20), max_retry=50, () => {
      let runtime_ids = native_ws_runtime_ids_for_app(app)
      guard runtime_ids.length() == 2 else {
        raise WebSocketLifecycleServerNotReady
      }
      let mut room_members = 0
      for runtime_id in runtime_ids {
        room_members += native_ws_channel_member_count_in_runtime(
          runtime_id, "room",
        )
      }
      guard room_members == 2 else { raise WebSocketLifecycleServerNotReady }
    })

    shutdown.put(())
    let client1_after = @async.with_timeout_opt(300, () => {
      try client1.recv().read_all().text() catch {
        err => Err(err)
      } noraise {
        text => Ok(text)
      }
    })
    let client2_after = @async.with_timeout_opt(300, () => {
      try client2.recv().read_all().text() catch {
        err => Err(err)
      } noraise {
        text => Ok(text)
      }
    })

    match client1_after {
      Some(Err(@websocket.ConnectionClosed(GoingAway, Some(reason)))) => {
        debug_inspect(
          reason,
          content=(
            #|"websocket server shutdown"
          ),
        )
        match client2_after {
          None => ()
          Some(Err(@websocket.ConnectionClosed(code, why))) =>
            fail(
              "expected only one reused runtime to stop after shutdown signal, but both websocket clients closed: \{@debug.to_string(code)} / \{@debug.to_string(why)}",
            )
          Some(Err(err)) => raise err
          Some(Ok(text)) =>
            fail(
              "expected sibling reused websocket runtime to stay alive after shutdown signal, got text: \{text}",
            )
        }
        match @async.with_timeout_opt(200, () => task1.wait()) {
          Some(_) => ()
          None => fail("timed out waiting for signaled reused runtime to stop")
        }
        @async.retry(FixedDelay(20), max_retry=50, () => {
          let runtime_ids = native_ws_runtime_ids_for_app(app)
          guard runtime_ids.length() == 1 else {
            raise WebSocketLifecycleServerNotReady
          }
          let surviving_runtime_id = runtime_ids[0]
          guard native_ws_channel_member_count_in_runtime(
              surviving_runtime_id, "room",
            ) ==
            1 else {
            raise WebSocketLifecycleServerNotReady
          }
        })
        match @async.with_timeout_opt(100, () => task2.wait()) {
          Some(_) =>
            fail(
              "expected sibling reused runtime to stay alive after one shutdown signal",
            )
          None => ()
        }
        client2.send_text("publish")
        debug_inspect(
          client2.recv().read_all().text(),
          content=(
            #|"fanout"
          ),
        )
        shutdown.close()
        match @async.with_timeout_opt(200, () => task2.wait()) {
          Some(_) => ()
          None =>
            fail(
              "timed out waiting for the surviving reused runtime to stop after queue close",
            )
        }
        @async.retry(FixedDelay(20), max_retry=50, () => {
          guard native_ws_runtime_ids_for_app(app).is_empty() else {
            raise WebSocketLifecycleServerNotReady
          }
        })
      }
      Some(Err(@websocket.ConnectionClosed(code, reason))) =>
        fail(
          "expected stopped reused websocket client to observe going-away close after shutdown signal, got \{@debug.to_string(code)} / \{@debug.to_string(reason)}",
        )
      Some(Err(err)) => raise err
      Some(Ok(text)) =>
        fail(
          "expected stopped reused websocket client to observe shutdown close, got text: \{text}",
        )
      None =>
        match client2_after {
          Some(Err(@websocket.ConnectionClosed(GoingAway, Some(reason)))) => {
            debug_inspect(reason, content="websocket server shutdown")
            match @async.with_timeout_opt(200, () => task2.wait()) {
              Some(_) => ()
              None =>
                fail("timed out waiting for signaled reused runtime to stop")
            }
            @async.retry(FixedDelay(20), max_retry=50, () => {
              let runtime_ids = native_ws_runtime_ids_for_app(app)
              guard runtime_ids.length() == 1 else {
                raise WebSocketLifecycleServerNotReady
              }
              let surviving_runtime_id = runtime_ids[0]
              guard native_ws_channel_member_count_in_runtime(
                  surviving_runtime_id, "room",
                ) ==
                1 else {
                raise WebSocketLifecycleServerNotReady
              }
            })
            match @async.with_timeout_opt(100, () => task1.wait()) {
              Some(_) =>
                fail(
                  "expected sibling reused runtime to stay alive after one shutdown signal",
                )
              None => ()
            }
            client1.send_text("publish")
            debug_inspect(client1.recv().read_all().text(), content="fanout")
            shutdown.close()
            match @async.with_timeout_opt(200, () => task1.wait()) {
              Some(_) => ()
              None =>
                fail(
                  "timed out waiting for the surviving reused runtime to stop after queue close",
                )
            }
            @async.retry(FixedDelay(20), max_retry=50, () => {
              guard native_ws_runtime_ids_for_app(app).is_empty() else {
                raise WebSocketLifecycleServerNotReady
              }
            })
          }
          Some(Err(@websocket.ConnectionClosed(code, reason))) =>
            fail(
              "expected exactly one reused websocket runtime to stop after shutdown signal, but got unexpected second close: \{@debug.to_string(code)} / \{@debug.to_string(reason)}",
            )
          Some(Err(err)) => raise err
          Some(Ok(text)) =>
            fail(
              "expected a reused websocket runtime to stop after shutdown signal, got text: \{text}",
            )
          None =>
            fail(
              "expected exactly one reused websocket runtime to stop after shutdown signal",
            )
        }
    }
  }) catch {
    WebSocketLifecycleSocketBindUnavailable => return
    err => raise err
  }
}

// Pure-internal whitebox tests (ensure_native_ws_hub, register_native_ws_connection,
// ws_subscribe, decode_native_ws_message, chunk-size helpers, cleanup) moved to
// websocket/runtime_wbtest.mbt for direct access to private hub state.
