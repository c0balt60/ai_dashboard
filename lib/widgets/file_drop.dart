/// Files pasted or dropped onto the page. Only browsers have those, so other
/// platforms get a listener that never fires.
library;

export 'file_drop_stub.dart' if (dart.library.js_interop) 'file_drop_web.dart';
