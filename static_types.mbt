// Public types and the provider trait for static-asset serving.
// Implemented by static_file/StaticFileProvider; consumed by
// App::static_assets in static_assets.mbt.

///|
/// Metadata describing a static asset including its content type, ETag, modification time, and size.
pub(all) struct StaticAssetMeta {
  /// MIME type of the asset (e.g., `"text/css"`, `"image/png"`).
  asset_type : String?
  /// Entity tag for cache validation (e.g., `"W/\"16af-1234\""`).
  etag : String?
  /// Last modification time as a Unix timestamp in seconds.
  mtime : Int64?
  /// Filesystem path to the resolved asset.
  path : String?
  /// File size in bytes.
  size : Int64?
  /// Content encoding if pre-compressed (e.g., `"gzip"`, `"br"`).
  encoding : String?
}

///|
/// Creates a new `StaticAssetMeta` with optional fields for asset type, ETag, mtime, path, size, and encoding.
pub fn StaticAssetMeta::StaticAssetMeta(
  asset_type? : String,
  etag? : String,
  mtime? : Int64,
  path? : String,
  size? : Int64,
  encoding? : String,
) -> Self {
  { asset_type, etag, mtime, path, size, encoding }
}

///|
/// Trait for providing static file serving capabilities, including asset lookup, content retrieval, and MIME type resolution.
pub(open) trait ServeStaticProvider {
  // This function should resolve asset meta
  async fn get_meta(Self, id : String) -> StaticAssetMeta? noraise
  // This function should resolve asset content
  async fn get_contents(Self, id : String) -> &Responder noraise
  // Custom MIME type resolver function
  fn get_type(Self, ext : String) -> String? noraise
  // Encodings map
  fn get_encodings(Self) -> Map[String, String] noraise
  // Index names
  fn get_index_names(Self) -> Array[String] noraise
  // Fallthrough
  fn get_fallthrough(Self) -> Bool noraise
}
