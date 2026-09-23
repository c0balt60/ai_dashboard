/// Opens the WebSocket to the PC server. Native builds send pings every 20s
/// so a dead connection (say, after the phone switches networks) is noticed
/// and replaced; browsers handle keep-alive themselves.
library;

export 'socket_connect_web.dart' if (dart.library.io) 'socket_connect_io.dart';
