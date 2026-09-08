// Parser implementation for RFC 3986 URI references.

// RFC 3986 Parsing Functions

// URI-reference = scheme ":" "//" authority path-abempty [ "?" query ] [ "#" fragment ]
//               / scheme ":" "/" [ segment-nz *( "/" segment ) ] [ "?" query ] [ "#" fragment ]
//               / scheme ":" segment-nz *( "/" segment ) [ "?" query ] [ "#" fragment ]
//               / scheme ":" [ "?" query ] [ "#" fragment ]
//               / "//" authority path-abempty [ "?" query ] [ "#" fragment ]
//               / "/" [ segment-nz *( "/" segment ) ] [ "?" query ] [ "#" fragment ]
//               / segment-nz-nc *( "/" segment ) [ "?" query ] [ "#" fragment ]
//               / [ "?" query ] [ "#" fragment ]

///|
fn parse_scheme_or_segment_nz_nc(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  let segment = source
  for s = source {
    match s {
      [':', .. k] as s => {
        uri.scheme = Some(source.slice_before(s))
        return parse_hier_part_then_query(k, uri)
      }
      ['/', .. k] as s => {
        uri.path.push(segment.slice_before(s))
        return parse_path_abempty_then_query(k, uri)
      }
      ['?', .. k] as s => {
        uri.path.push(segment.slice_before(s))
        return parse_query_then_fragment(k, uri)
      }
      ['#', .. k] as s => {
        uri.path.push(segment.slice_before(s))
        // '#' introduces a fragment directly (no query present here).
        // Previously this incorrectly called parse_query_then_fragment,
        // causing the fragment to end up in uri.query.
        return parse_fragment(k, uri)
      }
      [b, .. k] if is_unreserved(b) || is_sub_delim(b) || b == '@' => continue k
      [] => {
        // EOF after a bare segment (e.g. "foo", ".", "..").
        // Push the accumulated segment and return.
        uri.path.push(segment)
        return s
      }
      _ => raise InvalidSchemeOrSegment(source)
    }
  }
}

///|
fn parse_uri_reference(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  match source {
    [.. "//", .. k] => {
      // relative-ref > relative-part > "//" authority path-abempty
      let k = parse_authority(k, uri)
      parse_path_abempty_then_query(k, uri)
    }
    ['/', .. k] =>
      // relative-ref > relative-part > "/" [ segment-nz *( "/" segment ) ] [ "?" query ] [ "#" fragment ]
      parse_path_abempty_then_query(k, uri)
    ['?', .. k] =>
      // relative-ref > relative-part > "?" query
      parse_query_then_fragment(k, uri)
    ['#', .. k] =>
      // relative-ref > relative-part > "#" fragment
      parse_fragment(k, uri)
    [..] as s => parse_scheme_or_segment_nz_nc(s, uri)
  }
}

///|
/// Parses a URI-reference from raw bytes following RFC 3986, returning a fully
/// populated `Uri` structure or raising a `ParseError` on invalid input.
pub fn Uri::Uri(source : StringView) -> Uri raise ParseError {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  let source = parse_uri_reference(source, uri)
  if !(source is []) {
    raise Invalid(source)
  }
  uri
}

///|
fn parse_scheme(source : StringView, uri : Uri) -> StringView raise ParseError {
  match source {
    [b, .. k] if is_alpha(b) =>
      for s = k {
        match s {
          [b, .. s] if is_alpha(b) ||
            is_digit(b) ||
            b == '+' ||
            b == '-' ||
            b == '.' => continue s
          [':', .. k] as s => {
            uri.scheme = Some(source.slice_before(s))
            return k
          }
          [_, ..] as s => raise InvalidScheme(s)
          [] => raise MissingColon
        }
      }
    [_, ..] as s => raise InvalidScheme(s)
    [] => raise MissingScheme
  }
}

///|
fn parse_percent_encoding(source : StringView) -> StringView raise ParseError {
  match source {
    [
      '0'..='9'
      | 'A'..='F'
      | 'a'..='f',
      '0'..='9'
      | 'A'..='F'
      | 'a'..='f',
      .. source,
    ] => source
    [..] => raise InvalidPercentEncoding(source)
  }
}

///|
fn parse_userinfo(
  source : StringView,
  authority : Authority,
) -> StringView raise ParseError {
  let start = source
  for s = source {
    match s {
      ['@', .. k] as s => {
        authority.userinfo = Some(start.slice_before(s))
        return k
      }
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_unreserved(b) || is_sub_delim(b) || b == ':' => continue k
      [_, ..] as s => raise InvalidHeirPart(s)
      [] as s => return s
    }
  }
}

///|
fn parse_reg_name(
  source : StringView,
  authority : Authority,
) -> StringView raise ParseError {
  for s = source {
    match s {
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_unreserved(b) || is_sub_delim(b) => continue k
      _ as s => {
        authority.host = RegName(source.slice_before(s))
        return s
      }
    }
  }
}

///|
fn parse_ipv6_address(
  source : StringView,
  authority : Authority,
) -> StringView raise ParseError {
  // Simplified IPv6 parsing - match until ']'
  for s = source {
    match s {
      [']', .. k] as s => {
        authority.host = IPv6Address(source.slice_before(s))
        return k
      }
      [b, .. s] if is_hexdig(b) || b == ':' || b == '.' => continue s
      _ as s => raise InvalidHeirPart(s)
    }
  }
}

///|
fn parse_host(
  source : StringView,
  authority : Authority,
) -> StringView raise ParseError {
  // Try IP literal first
  match source {
    ['[', .. k] => parse_ipv6_address(k, authority)
    _ =>
      // Try IPv4 address, fallback to reg-name
      parse_reg_name(source, authority)
  }
}

///|
fn parse_port(source : StringView, authority : Authority) -> StringView {
  match source {
    [':', .. k] => {
      let mut port_val = 0
      for s = k {
        match s {
          [d, .. s] if is_digit(d) => {
            port_val = port_val * 10 + (d.to_int() - '0')
            continue s
          }
          _ as s => {
            authority.port = Some(port_val)
            return s
          }
        }
      }
    }
    _ => source
  }
}

///|
fn parse_authority(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  let authority = Authority::{ userinfo: None, host: RegName(""), port: None, }
  uri.authority = Some(authority)

  // Try to parse userinfo first
  let remaining = parse_userinfo(source, authority) catch {
    _ => source // No userinfo, continue with host
  }
  let remaining = parse_host(remaining, authority)
  parse_port(remaining, authority)
}

///|
fn parse_segment(
  source : StringView,
) -> (StringView, StringView) raise ParseError {
  let start = source
  for s = source {
    match s {
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_pchar(b) => continue k
      _ as s => return (s, start.slice_before(s))
    }
  }
}

///|
/// Continuation-based completion functions
fn parse_done(source : StringView, _ : Uri) -> StringView {
  source
}

///|
fn parse_fragment(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  for s = source {
    match s {
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_pchar(b) || b == '/' || b == '?' => continue k
      [..] as s => {
        uri.fragment = Some(source.slice_before(s))
        return s
      }
    }
  }
}

///|
fn parse_query_then_fragment(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  let start = source
  for s = source {
    match s {
      ['#', .. k] as s => {
        uri.query = Some(start.slice_before(s))
        return parse_fragment(k, uri)
      }
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_pchar(b) || b == '/' || b == '?' => continue k
      [..] as s => {
        uri.query = Some(start.slice_before(s))
        return s
      }
    }
  }
}

///|
fn parse_path_abempty_then_query(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  for s = source {
    match s {
      ['%', .. k] => continue parse_percent_encoding(k)
      ['/', .. k] as s => {
        let segment = source.slice_before(s)
        if segment != "" {
          uri.path.push(segment)
        }
        return parse_path_abempty_then_query(k, uri)
      }
      ['?', .. k] as s => {
        let segment = source.slice_before(s)
        if segment != "" {
          uri.path.push(segment)
        }
        return parse_query_then_fragment(k, uri)
      }
      ['#', .. k] as s => {
        let segment = source.slice_before(s)
        if segment != "" {
          uri.path.push(segment)
        }
        return parse_fragment(k, uri)
      }
      [b, .. k] if is_pchar(b) => continue k
      [] as s => {
        let segment = source.slice_before(s)
        if segment != "" {
          uri.path.push(segment)
        }
        return s
      }
      [..] as s => raise InvalidSegment(s)
    }
  }
}

///|
fn parse_hier_part_then_query(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  match source {
    [.. "//", .. k] =>
      match parse_authority(k, uri) {
        ['/', .. k] => parse_path_abempty_then_query(k, uri)
        ['?', .. k] => parse_query_then_fragment(k, uri)
        ['#', ..] => parse_fragment(k, uri)
        [] => parse_done(k, uri)
        [..] as s => raise Invalid(s)
      }
    _ => parse_path_abempty_then_query(source, uri)
  }
}

///|
fn parse_absolute_uri(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  let remaining = parse_scheme(source, uri) // already consumes the ':'
  parse_hier_part_then_query_no_fragment(remaining, uri)
}

///|
fn parse_hier_part_then_query_no_fragment(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  match source {
    [.. "//", .. k] => {
      let remaining = parse_authority(k, uri)
      parse_path_abempty_then_query_no_fragment(remaining, uri)
    }
    _ => parse_path_abempty_then_query_no_fragment(source, uri)
  }
}

///|
fn parse_path_abempty_then_query_no_fragment(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  for s = source {
    match s {
      ['/', .. k] => {
        let (remaining, segment_val) = parse_segment(k)
        if segment_val != "" {
          uri.path.push(segment_val)
        }
        continue remaining
      }
      _ as s => return parse_query_no_fragment_or_done(s, uri)
    }
  }
}

///|
fn parse_query_no_fragment_or_done(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  match source {
    ['?', .. k] => parse_query_no_fragment_then_done(k, uri)
    _ => parse_done(source, uri)
  }
}

///|
fn parse_query_no_fragment_then_done(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  let start = source
  for s = source {
    match s {
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_pchar(b) || b == '/' || b == '?' => continue k
      _ as s => {
        uri.query = Some(start.slice_before(s))
        return parse_done(s, uri)
      }
    }
  }
}

///|
fn remove_dot_segments(path : Array[StringView]) -> Array[StringView] {
  let output = []
  for segment in path {
    if segment == "." {
      continue // Remove single dot segments
    } else if segment == ".." {
      if output.length() > 0 {
        output.pop() |> ignore() // Remove last segment and the .. segment
      }
      // If output is empty, ignore the .. segment
    } else {
      output.push(segment)
    }
  }
  output
}
