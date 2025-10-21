import 'package:flutter/widgets.dart';

/// Shared RouteObserver used across the app so pages can react to navigation events.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();
