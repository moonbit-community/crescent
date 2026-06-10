///|
fn request_content_length(request : @http.Request) -> Int? {
  match
    @httputil.get_header_case_insensitive(request.headers, "content-length") {
    Some(value) => Some(@string.parse_int(value) catch { _ => return None })
    None => None
  }
}

///|
priv enum RequestBodyReadOutcome {
  Body(Bytes)
  RequestRejected
}

///|
fn next_native_request_body_chunk_size(limit : Int, total : Int) -> Int {
  let remaining = limit - total
  if remaining >= 1024 {
    1024
  } else {
    remaining + 1
  }
}

///|
test "next_native_request_body_chunk_size returns 1024 when remaining >= 1024" {
  inspect(next_native_request_body_chunk_size(2048, 0), content="1024")
  inspect(next_native_request_body_chunk_size(2048, 1024), content="1024")
  inspect(next_native_request_body_chunk_size(4096, 2000), content="1024")
}

///|
test "next_native_request_body_chunk_size returns remaining + 1 when remaining < 1024" {
  inspect(next_native_request_body_chunk_size(1000, 0), content="1001")
  inspect(next_native_request_body_chunk_size(2048, 1500), content="549")
  inspect(next_native_request_body_chunk_size(100, 99), content="2")
  inspect(next_native_request_body_chunk_size(100, 100), content="1")
}

///|
test "native request body limit helpers handle int max boundaries" {
  let max_int = 2_147_483_647
  inspect(next_native_request_body_chunk_size(max_int, 0), content="1024")
  inspect(
    native_request_body_chunk_exceeds_limit(max_int, max_int, 1),
    content="true",
  )
  inspect(
    native_request_body_chunk_exceeds_limit(max_int, max_int - 1, 1),
    content="false",
  )
}

///|
fn native_request_body_chunk_exceeds_limit(
  limit : Int,
  total : Int,
  chunk_length : Int,
) -> Bool {
  chunk_length > limit - total
}

///|
test "native_request_body_chunk_exceeds_limit returns true when chunk exceeds remaining" {
  inspect(native_request_body_chunk_exceeds_limit(100, 90, 11), content="true")
  inspect(native_request_body_chunk_exceeds_limit(100, 100, 1), content="true")
}

///|
test "native_request_body_chunk_exceeds_limit returns false when chunk fits" {
  inspect(native_request_body_chunk_exceeds_limit(100, 90, 10), content="false")
  inspect(native_request_body_chunk_exceeds_limit(100, 0, 100), content="false")
  inspect(native_request_body_chunk_exceeds_limit(100, 50, 1), content="false")
}

///|
async fn read_request_body_async(
  request : @http.Request,
  body_reader : &@io.Reader,
  conn : @http.ServerConnection,
  max_request_body_bytes : Int?,
) -> RequestBodyReadOutcome {
  match max_request_body_bytes {
    None => Body(body_reader.read_all().binary())
    Some(limit) => {
      match request_content_length(request) {
        Some(content_length) if content_length > limit => {
          send_request_entity_too_large_async(request, conn)
          return RequestRejected
        }
        _ => ()
      }
      let buffer = Buffer()
      let mut total = 0
      for ;; {
        let next_chunk_size = next_native_request_body_chunk_size(limit, total)
        guard body_reader.read_some(max_len=next_chunk_size) is Some(chunk) else {
          return Body(buffer.contents())
        }
        if native_request_body_chunk_exceeds_limit(limit, total, chunk.length()) {
          send_request_entity_too_large_async(request, conn)
          return RequestRejected
        }
        total += chunk.length()
        buffer.write_bytes(chunk)
      }
    }
  }
}

///|
async fn read_request_body_with_policy_async(
  request : @http.Request,
  body_reader : &@io.Reader,
  conn : @http.ServerConnection,
  max_request_body_bytes : Int?,
  request_body_read_timeout_ms : Int?,
) -> RequestBodyReadOutcome {
  match request_body_read_timeout_ms {
    Some(request_body_read_timeout_ms) =>
      match
        @async.with_timeout_opt(request_body_read_timeout_ms, () => {
          read_request_body_async(
            request, body_reader, conn, max_request_body_bytes,
          )
        }) {
        Some(outcome) => outcome
        None => {
          send_request_timeout_async(request, conn)
          RequestRejected
        }
      }
    None =>
      read_request_body_async(
        request, body_reader, conn, max_request_body_bytes,
      )
  }
}
