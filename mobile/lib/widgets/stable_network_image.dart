import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// An image provider that caches by the object path instead of the full
/// pre-signed URL. Cloud storage signs URLs with a short-lived token in the
/// query string, so the same cover has a *new* URL on every fetch; the default
/// [NetworkImage] keys the cache on the whole URL, so each reload downloads a
/// fresh copy and leaves a stale high-resolution entry behind.
///
/// [StableNetworkImage] strips the query string for the cache identity (the
/// path is stable) while still fetching the signed URL, so re-renders and
/// reloads reuse the decoded frame instead of re-downloading the image.
class StableNetworkImage extends ImageProvider<StableNetworkImage> {
  final String url;
  final double scale;
  final NetworkImage _delegate;

  StableNetworkImage(String url, {double scale = 1.0})
      : url = url,
        scale = scale,
        _delegate = NetworkImage(url, scale: scale);

  String get stableKey {
    final idx = url.indexOf('?');
    return idx < 0 ? url : url.substring(0, idx);
  }

  // Debug label for the image cache; the stable path (no presign query).
  String get keyName => stableKey;

  @override
  Future<StableNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<StableNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
      StableNetworkImage key, ImageDecoderCallback decode) {
    return _delegate.loadImage(key._delegate, decode);
  }

  @override
  bool operator ==(Object other) =>
      other is StableNetworkImage &&
      other.stableKey == stableKey &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(stableKey, scale);
}
