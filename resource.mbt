///|
/// Configuration for registering a RESTful resource with standard CRUD routes.
pub struct ResourceConfig {
  /// GET /path — list all resources
  list : (async (Event) -> &Responder)?
  /// GET /path/:id — get a single resource by ID
  get : (async (Event) -> &Responder)?
  /// POST /path — create a new resource
  create : (async (Event) -> &Responder)?
  /// PUT /path/:id — update an existing resource
  update : (async (Event) -> &Responder)?
  /// DELETE /path/:id — delete a resource
  delete : (async (Event) -> &Responder)?
}

///|
/// Creates a new `ResourceConfig` with optional CRUD handlers.
pub fn ResourceConfig::ResourceConfig(
  list? : async (Event) -> &Responder,
  get? : async (Event) -> &Responder,
  create? : async (Event) -> &Responder,
  update? : async (Event) -> &Responder,
  delete? : async (Event) -> &Responder,
) -> ResourceConfig {
  { list, get, create, update, delete, }
}

///|
/// Registers standard REST routes (list, get, create, update, delete) for a resource path.
pub fn App::resource(
  self : App,
  path : String,
  config : ResourceConfig,
) -> Unit {
  match config.list {
    Some(handler) => self.get(path, handler)
    None => ()
  }
  match config.get {
    Some(handler) => self.get(path + "/:id", handler)
    None => ()
  }
  match config.create {
    Some(handler) => self.post(path, handler)
    None => ()
  }
  match config.update {
    Some(handler) => self.put(path + "/:id", handler)
    None => ()
  }
  match config.delete {
    Some(handler) => self.delete(path + "/:id", handler)
    None => ()
  }
}
