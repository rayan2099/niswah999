import 'package:flutter/widgets.dart';

/// Shared visibility signals for surfaces that must not mark hidden content
/// read or suppress phone alerts while a different route is on top.
final appRouteObserver = RouteObserver<ModalRoute<dynamic>>();
