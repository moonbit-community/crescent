// Hub state, connection registry, pub/sub primitives, and public
// introspection helpers for the websocket runtime. Intra-package siblings
// of websocket/lifecycle.mbt (handshake + message loop + handle_route_async).

///|
priv struct NativeWebSocketConnection {
  outgoing : @async.Queue[NativeWebSocketOutbound]
  overflow_policy : NativeWebSocketOverflowPolicy
  subscribed_channels : Map[String, Unit]
}

///|
priv struct NativeWebSocketHub {
  connection_counter : Ref[Int]
  connections : Map[String, NativeWebSocketConnection]
  channels : Map[String, Map[String, Unit]]
}

///|
priv enum NativeWebSocketOutbound {
  SendText(String)
  SendBinary(Bytes)
}

///|
let native_ws_hubs : Map[String, NativeWebSocketHub] = Map([])

///|
let native_ws_connection_hubs : Map[String, String] = Map([])

///|
/// Default per-connection capacity for the outbound WebSocket message queue,
/// used when `NativeServeOptions::websocket_outgoing_queue_capacity` is None.
pub const DEFAULT_OUTGOING_QUEUE_CAPACITY : Int = 256

///|
fn ensure_native_ws_hub(runtime_id : String) -> NativeWebSocketHub {
  match native_ws_hubs.get(runtime_id) {
    Some(hub) => hub
    None => {
      let hub : NativeWebSocketHub = {
        connection_counter: Ref(0),
        connections: Map([]),
        channels: Map([]),
      }
      native_ws_hubs.set(runtime_id, hub)
      hub
    }
  }
}

///|
fn resolve_native_ws_connection(
  connection_id : String,
) -> (NativeWebSocketHub, NativeWebSocketConnection)? {
  match native_ws_connection_hubs.get(connection_id) {
    Some(runtime_id) =>
      match native_ws_hubs.get(runtime_id) {
        Some(hub) =>
          match hub.connections.get(connection_id) {
            Some(connection) => Some((hub, connection))
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn next_native_ws_connection_id(
  runtime_id : String,
  hub : NativeWebSocketHub,
) -> String {
  hub.connection_counter.val += 1
  "\{runtime_id}:\{hub.connection_counter.val}"
}

///|
fn snapshot_native_ws_channels(connection_id : String) -> Array[String] {
  match resolve_native_ws_connection(connection_id) {
    Some((_, connection)) => {
      let channels : Array[String] = []
      connection.subscribed_channels.each((channel, _) => channels.push(channel))
      channels
    }
    None => []
  }
}

///|
fn snapshot_native_ws_peer(
  connection_id : String,
  params : Map[String, String],
) -> WebSocketPeer {
  {
    connection_id,
    subscribed_channels: snapshot_native_ws_channels(connection_id),
    params,
  }
}

///|
fn register_native_ws_connection(
  runtime_id : String,
  connection_id : String,
  outgoing : @async.Queue[NativeWebSocketOutbound],
  overflow_policy : NativeWebSocketOverflowPolicy,
) -> Unit {
  let hub = ensure_native_ws_hub(runtime_id)
  hub.connections.set(connection_id, {
    outgoing,
    overflow_policy,
    subscribed_channels: Map([]),
  })
  native_ws_connection_hubs.set(connection_id, runtime_id)
}

///|
fn remove_native_ws_channel_member(
  hub : NativeWebSocketHub,
  channel : String,
  connection_id : String,
) -> Unit {
  match hub.channels.get(channel) {
    Some(members) => {
      if members.get(connection_id) is Some(_) {
        ignore(members.remove(connection_id))
      }
      if members.is_empty() {
        ignore(hub.channels.remove(channel))
      }
    }
    None => ()
  }
}

///|
fn unregister_native_ws_connection(connection_id : String) -> Unit {
  match native_ws_connection_hubs.get(connection_id) {
    Some(runtime_id) =>
      match native_ws_hubs.get(runtime_id) {
        Some(hub) =>
          match hub.connections.get(connection_id) {
            Some(connection) => {
              let channels = snapshot_native_ws_channels(connection_id)
              for channel in channels {
                remove_native_ws_channel_member(hub, channel, connection_id)
              }
              connection.outgoing.close()
              ignore(hub.connections.remove(connection_id))
              ignore(native_ws_connection_hubs.remove(connection_id))
              if hub.connections.is_empty() && hub.channels.is_empty() {
                ignore(native_ws_hubs.remove(runtime_id))
              }
            }
            None => ()
          }
        None => ()
      }
    None => ()
  }
}

///|
fn enqueue_native_ws_outgoing(
  connection_id : String,
  message : NativeWebSocketOutbound,
) -> Unit {
  match resolve_native_ws_connection(connection_id) {
    Some((_, connection)) =>
      enqueue_native_ws_outgoing_to_connection(connection, message)
    None => ()
  }
}

///|
fn enqueue_native_ws_outgoing_to_connection(
  connection : NativeWebSocketConnection,
  message : NativeWebSocketOutbound,
) -> Unit {
  let enqueued = connection.outgoing.try_put(message) catch { _ => return }
  if enqueued {
    return
  }
  match connection.overflow_policy {
    DropOldest =>
      try {
        ignore(connection.outgoing.try_get())
        ignore(connection.outgoing.try_put(message))
      } catch {
        _ => ()
      }
    DropLatest => ()
  }
}

///|
fn ws_send(id : String, msg : String) -> Unit {
  enqueue_native_ws_outgoing(id, SendText(msg))
}

///|
fn ws_send_bytes(id : String, msg : Bytes) -> Unit {
  enqueue_native_ws_outgoing(id, SendBinary(msg))
}

///|
fn ws_subscribe(id : String, channel : String) -> Unit {
  match resolve_native_ws_connection(id) {
    Some((hub, connection)) => {
      if connection.subscribed_channels.get(channel) is Some(_) {
        return
      }
      connection.subscribed_channels.set(channel, ())
      match hub.channels.get(channel) {
        Some(members) => members.set(id, ())
        None => {
          let members : Map[String, Unit] = Map([])
          members.set(id, ())
          hub.channels.set(channel, members)
        }
      }
    }
    None => ()
  }
}

///|
fn ws_unsubscribe(id : String, channel : String) -> Unit {
  match resolve_native_ws_connection(id) {
    Some((hub, connection)) => {
      if connection.subscribed_channels.get(channel) is Some(_) {
        ignore(connection.subscribed_channels.remove(channel))
      }
      remove_native_ws_channel_member(hub, channel, id)
    }
    None => ()
  }
}

///|
fn ws_publish(connection_id : String, channel : String, msg : String) -> Unit {
  match resolve_native_ws_connection(connection_id) {
    Some((hub, _)) =>
      match hub.channels.get(channel) {
        Some(members) => {
          let connection_ids : Array[String] = []
          members.each((member_id, _) => connection_ids.push(member_id))
          for member_id in connection_ids {
            ws_send(member_id, msg)
          }
        }
        None => ()
      }
    None => ()
  }
}

///|
/// Returns all currently registered runtime IDs. Intended for tests and
/// debugging; production code should not need this.
pub fn registered_runtime_ids() -> Array[String] {
  let result : Array[String] = []
  native_ws_hubs.each((runtime_id, _) => result.push(runtime_id))
  result
}

///|
/// Returns the number of currently registered WebSocket runtimes.
pub fn registered_runtime_count() -> Int {
  let mut count = 0
  native_ws_hubs.each((_, _) => count += 1)
  count
}

///|
/// Returns true if the given runtime ID has a registered hub.
pub fn runtime_is_registered(runtime_id : String) -> Bool {
  native_ws_hubs.get(runtime_id) is Some(_)
}

///|
/// Returns the number of registered WebSocket connections across all runtimes.
pub fn registered_connection_count() -> Int {
  let mut count = 0
  native_ws_connection_hubs.each((_, _) => count += 1)
  count
}

///|
/// Returns true if the given connection ID is registered with any runtime.
pub fn connection_is_registered(connection_id : String) -> Bool {
  native_ws_connection_hubs.get(connection_id) is Some(_)
}

///|
/// Returns the runtime ID that owns this connection, or None if the
/// connection is not registered.
pub fn runtime_id_for_connection(connection_id : String) -> String? {
  native_ws_connection_hubs.get(connection_id)
}

///|
/// Returns the number of subscribers to the given channel across all runtimes.
pub fn channel_member_count(channel : String) -> Int {
  let mut count = 0
  native_ws_hubs.each((_runtime_id, hub) => {
    match hub.channels.get(channel) {
      Some(members) => members.each((_, _) => count += 1)
      None => ()
    }
  })
  count
}

///|
/// Returns the number of subscribers to the given channel within a specific
/// runtime, or 0 if the runtime is not registered.
pub fn channel_member_count_in_runtime(
  runtime_id : String,
  channel : String,
) -> Int {
  match native_ws_hubs.get(runtime_id) {
    Some(hub) =>
      match hub.channels.get(channel) {
        Some(members) => {
          let mut count = 0
          members.each((_, _) => count += 1)
          count
        }
        None => 0
      }
    None => 0
  }
}

///|
/// Tears down all hub state associated with a runtime ID: closes outgoing
/// queues, removes channel memberships, and drops the hub. Called via
/// `defer` from `App::serve_on` when serving ends, and used by tests to
/// reset state between cases. Safe to call on a runtime ID that was never
/// registered.
pub fn cleanup_runtime(runtime_id : String) -> Unit {
  match native_ws_hubs.get(runtime_id) {
    Some(hub) => {
      let connection_ids : Array[String] = []
      hub.connections.each((connection_id, _) => {
        connection_ids.push(connection_id)
      })
      for connection_id in connection_ids {
        unregister_native_ws_connection(connection_id)
      }
      ignore(native_ws_hubs.remove(runtime_id))
    }
    None => ()
  }
}
