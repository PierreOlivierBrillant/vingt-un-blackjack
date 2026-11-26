/// Sub-pages of the Rendez-vous tab, mounted under `/romance` by the router
/// (`/romance/<path>`). OWNER: Rendez-vous implementer: add your scene
/// player, gift shop, "Souvenirs" gallery and "Rencontres" pages HERE (the
/// router never needs editing). Full-screen pages (visual novel) should use
/// `parentNavigatorKey: rootKey` to cover the tab bar.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

List<RouteBase> romanceRoutes(GlobalKey<NavigatorState> rootKey) => const [];
