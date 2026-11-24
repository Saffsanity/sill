**Open a saved Mac from another app (2026-11-24, branch `ios-connect-links` from main at d9b3e995).**

The existing iOS URL scheme opens Sill with `sill://`. The new `sill://connect` action selects a paired Mac by ID or saved address. The saved Mac menu copies its ID link. An address selects a record, and the connection uses that record's usual routes and pinned key. A duplicate address needs a matching port or an ID link. An active session on a different Mac requires confirmation before switching.

The queued link gets the existing local discovery window on launch. A local row uses pinned TLS, and a remote dial uses the selected record's key. Pairing links still show their confirmation. The Mac app and the wire protocol stay the same.
