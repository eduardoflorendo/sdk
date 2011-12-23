// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// WARNING: Do not edit - generated code.

class _StorageWrappingImplementation extends DOMWrapperBase implements Storage {
  _StorageWrappingImplementation() : super() {}

  static create__StorageWrappingImplementation() native {
    return new _StorageWrappingImplementation();
  }

  int get length() { return _get_length(this); }
  static int _get_length(var _this) native;

  void clear() {
    _clear(this);
    return;
  }
  static void _clear(receiver) native;

  String getItem(String key_) {
    return _getItem(this, key_);
  }
  static String _getItem(receiver, key_) native;

  String key(int index) {
    return _key(this, index);
  }
  static String _key(receiver, index) native;

  void removeItem(String key_) {
    _removeItem(this, key_);
    return;
  }
  static void _removeItem(receiver, key_) native;

  void setItem(String key_, String data) {
    _setItem(this, key_, data);
    return;
  }
  static void _setItem(receiver, key_, data) native;

  String get typeName() { return "Storage"; }
}
