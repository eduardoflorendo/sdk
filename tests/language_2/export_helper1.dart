// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library export_helper1;

import 'export_helper2.dart';
export 'export_helper2.dart';

class Exported extends ReExported {}
