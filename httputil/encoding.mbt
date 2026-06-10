///|
fn hex_digit(b : Byte) -> Int? {
  if b >= b'0' && b <= b'9' {
    Some(b.to_int() - b'0'.to_int())
  } else if b >= b'a' && b <= b'f' {
    Some(b.to_int() - b'a'.to_int() + 10)
  } else if b >= b'A' && b <= b'F' {
    Some(b.to_int() - b'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// Decodes a percent-encoded URL text slice into a UTF-8 string.
///
/// Convenience wrapper around `url_decode` for callers that already have a
/// `StringView` (path segments, query strings, route params). RFC 3986 mandates
/// percent-encoding for any non-ASCII byte, so the view is encoded back to
/// UTF-8 bytes once before decoding.
pub fn url_decode_str(view : StringView) -> String {
  url_decode(@utf8.encode(view.to_owned())[:])
}

///|
/// Decodes a percent-encoded URL byte sequence into a UTF-8 string.
pub fn url_decode(bytes : BytesView) -> String {
  let len = bytes.length()
  let res = Array::make(len, b'\x00')
  let mut w = 0
  let mut r = 0
  while r < len {
    let b = bytes[r]
    if b == b'+' {
      res[w] = b' '
      w = w + 1
      r = r + 1
    } else if b == b'%' && r + 2 < len {
      match (hex_digit(bytes[r + 1]), hex_digit(bytes[r + 2])) {
        (Some(h1), Some(h2)) => {
          res[w] = (h1 * 16 + h2).to_byte()
          w = w + 1
          r = r + 3
        }
        _ => {
          res[w] = b'%'
          w = w + 1
          r = r + 1
        }
      }
    } else {
      res[w] = b
      w = w + 1
      r = r + 1
    }
  }
  let final_bytes = Bytes::from_array(res)
  let view = final_bytes[0:w]
  @utf8.decode(view) catch {
    _ => ""
  }
}

///|
/// Parses URL-encoded form data from a text slice into a map of key-value pairs.
///
/// Convenience wrapper around `parse_form_data` for callers that already have a
/// `StringView` (typically a query string pulled from a parsed URI).
pub fn parse_form_data_str(view : StringView) -> Map[String, String] {
  parse_form_data(@utf8.encode(view.to_string())[:])
}

///|
/// Parses URL-encoded form data (e.g. `key=value&foo=bar`) into a map of key-value pairs.
pub fn parse_form_data(bytes : BytesView) -> Map[String, String] {
  let res = Map([])
  if bytes.length() == 0 {
    return res
  }
  let mut start = 0
  let len = bytes.length()
  for i in 0..<len {
    if bytes[i] == b'&' {
      let part = bytes[start:i]
      parse_kv(part, res)
      start = i + 1
    }
  }
  if start < len {
    parse_kv(bytes[start:len], res)
  }
  res
}

///|
fn parse_kv(part : BytesView, map : Map[String, String]) -> Unit {
  let len = part.length()
  let mut eq_idx = -1
  for i in 0..<len {
    if part[i] == b'=' {
      eq_idx = i
      break
    }
  }
  if eq_idx != -1 {
    let key_bytes = part[0:eq_idx]
    let val_bytes = part[eq_idx + 1:len]
    let key = url_decode(key_bytes)
    let val = url_decode(val_bytes)
    if key != "" {
      map.set(key, val)
    }
  } else {
    let key = url_decode(part)
    if key != "" {
      map.set(key, "")
    }
  }
}

///|
fn is_unreserved(b : Byte) -> Bool {
  (b >= b'A' && b <= b'Z') ||
  (b >= b'a' && b <= b'z') ||
  (b >= b'0' && b <= b'9') ||
  b == b'-' ||
  b == b'_' ||
  b == b'.' ||
  b == b'~'
}

///|
/// Percent-encodes a string for use in URLs, escaping all characters except unreserved ones.
pub fn url_encode(s : String) -> String {
  let bytes = @utf8.encode(s)
  let buf = StringBuilder()
  for i in 0..<bytes.length() {
    let b = bytes[i]
    if is_unreserved(b) {
      match b.to_int().to_char() {
        Some(c) => buf.write_char(c)
        None => ()
      }
    } else {
      buf.write_char('%')
      let hex_bytes = b"0123456789ABCDEF"
      let h1 = (b.to_int() >> 4) & 0xF
      let h2 = b.to_int() & 0xF
      match hex_bytes[h1].to_int().to_char() {
        Some(c) => buf.write_char(c)
        None => ()
      }
      match hex_bytes[h2].to_int().to_char() {
        Some(c) => buf.write_char(c)
        None => ()
      }
    }
  }
  buf.to_string()
}

///|
/// Encodes a map of key-value pairs into a URL-encoded form string (e.g. `key=value&foo=bar`).
pub fn form_encode(map : Map[String, String]) -> String {
  let buf = StringBuilder()
  let mut first = true
  map.each((k, v) => {
    if !first {
      buf.write_char('&')
    }
    first = false
    buf.write_string(url_encode(k))
    buf.write_char('=')
    buf.write_string(url_encode(v))
  })
  buf.to_string()
}
