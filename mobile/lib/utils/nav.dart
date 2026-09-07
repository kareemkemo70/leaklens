// lib/utils/nav.dart
// Centralized, fast navigation helper.
// Replaces slow MaterialPageRoute slide animations with a crisp 200ms fade.

import 'package:flutter/material.dart';

/// A quick-fade page route — feels instant, no slow slide-in.
PageRouteBuilder<T> _fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );

/// Push a new page with a fast fade.
Future<T?> pushFade<T>(BuildContext context, Widget page) =>
    Navigator.push<T>(context, _fadeRoute(page));

/// Replace current page with a fast fade (no back button).
Future<T?> pushReplaceFade<T>(BuildContext context, Widget page) =>
    Navigator.pushReplacement<T, dynamic>(context, _fadeRoute(page));

/// Clear entire stack and go to [page] with a fast fade (used for logout / login).
Future<T?> pushAndRemoveAllFade<T>(BuildContext context, Widget page) =>
    Navigator.pushAndRemoveUntil<T>(context, _fadeRoute(page), (_) => false);
