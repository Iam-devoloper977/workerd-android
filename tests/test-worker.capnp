using Workerd = import "/workerd/workerd.capnp";

const config :Workerd.Config = (
  services = [
    (name = "hello", worker = .helloWorker),
    (name = "sqlite", worker = .sqliteWorker),
    (name = "disk", disk = (path = "do-data", writable = true))
  ],
  sockets = [
    (name = "http-hello", address = "127.0.0.1:18787", http = (), service = "hello"),
    (name = "http-sqlite", address = "127.0.0.1:18788", http = (), service = "sqlite")
  ]
);

const helloWorker :Workerd.Worker = (
  modules = [
    (name = "worker.js", esModule = embed "worker.js")
  ],
  compatibilityDate = "2025-01-01"
);

const sqliteWorker :Workerd.Worker = (
  modules = [
    (name = "sqlite.js", esModule = embed "sqlite.js")
  ],
  compatibilityDate = "2025-01-01",
  durableObjectNamespaces = [
    (className = "Counter", uniqueKey = "counter-key", enableSql = true)
  ],
  durableObjectStorage = (localDisk = "disk"),
  bindings = [
    (name = "COUNTER", durableObjectNamespace = "Counter")
  ]
);
