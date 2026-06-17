// packages/next_dart_protocol/lib/src/binary_codec.dart
//
// Compact binary (ndBinary) codec for the neutral declarative tree.
//
// Wire format summary
// -------------------
// All multi-byte integers are unsigned varints (little-endian, 7-bit groups,
// MSB of each byte is the continuation bit — same scheme as Protocol Buffers).
// Signed integers use zigzag encoding before varint serialization.
//
// Primitive types:
//   string  : varint(byteLength) + UTF-8 bytes
//   value   : 1-byte tag + payload
//             tag 0 = string  → string
//             tag 1 = int     → zigzag-varint (signed)
//             tag 2 = double  → 8 bytes IEEE 754 little-endian
//             tag 3 = bool    → 1 byte (0=false, 1=true)
//             tag 4 = argRef  → string (the arg name)
//             tag 5 = null    → (no payload)
//
// Compound types:
//   actionRef    : string(action) + varint(argCount) + [string(key) + value]...
//   node         : string(type)
//                + varint(propCount) + [string(key) + value]...
//                + varint(childCount) + [node]...
//                + varint(eventCount) + [string(eventName) + actionRef]...
//   componentDef : string(name)
//                + varint(paramCount) + [string]...
//                + node(body)
//   body (root)  : node(root)
//                + varint(componentCount) + [componentDef]...
//                + varint(dataCount) + [string(key) + value]...

import 'dart:convert';
import 'dart:typed_data';

import 'component.dart';
import 'envelope_body.dart';
import 'node.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Encode [body] to a compact binary blob.
Uint8List encodeTreeBinary(EnvelopeBody body) {
  final w = _Writer();
  _writeBody(w, body);
  return w.toBytes();
}

/// Decode a compact binary blob produced by [encodeTreeBinary].
EnvelopeBody decodeTreeBinary(Uint8List bytes) {
  final r = _Reader(bytes);
  return _readBody(r);
}

// ---------------------------------------------------------------------------
// Value tags
// ---------------------------------------------------------------------------

const int _tagString = 0;
const int _tagInt = 1;
const int _tagDouble = 2;
const int _tagBool = 3;
const int _tagArgRef = 4;
const int _tagNull = 5;

// ---------------------------------------------------------------------------
// Writer
// ---------------------------------------------------------------------------

class _Writer {
  final _buf = BytesBuilder();

  /// Write a single byte.
  void _writeByte(int b) => _buf.addByte(b);

  /// Write an unsigned varint (LEB128).
  void _writeVarint(int value) {
    assert(value >= 0, 'writeVarint expects non-negative value');
    while (value >= 0x80) {
      _writeByte((value & 0x7F) | 0x80);
      value >>= 7;
    }
    _writeByte(value & 0x7F);
  }

  /// Zigzag-encode a signed int, then write as varint.
  void _writeSignedVarint(int value) {
    // Zigzag: (n << 1) ^ (n >> 63)  — avoids large varints for negatives.
    final encoded = (value << 1) ^ (value >> 63);
    _writeVarint(encoded);
  }

  /// Write a length-prefixed UTF-8 string.
  void _writeString(String s) {
    final bytes = utf8.encode(s);
    _writeVarint(bytes.length);
    _buf.add(bytes);
  }

  /// Write a tagged value (prop value or data value).
  void _writeValue(Object? v) {
    if (v == null) {
      _writeByte(_tagNull);
    } else if (v is NdArgRef) {
      _writeByte(_tagArgRef);
      _writeString(v.name);
    } else if (v is bool) {
      // bool must come before int because in Dart, bool is NOT a subtype of int.
      _writeByte(_tagBool);
      _writeByte(v ? 1 : 0);
    } else if (v is int) {
      _writeByte(_tagInt);
      _writeSignedVarint(v);
    } else if (v is double) {
      _writeByte(_tagDouble);
      final bd = ByteData(8)..setFloat64(0, v, Endian.little);
      _buf.add(bd.buffer.asUint8List());
    } else if (v is String) {
      _writeByte(_tagString);
      _writeString(v);
    } else {
      throw ArgumentError('Unsupported value type ${v.runtimeType}: $v');
    }
  }

  /// Write an [NdActionRef].
  void _writeActionRef(NdActionRef ref) {
    _writeString(ref.action);
    _writeVarint(ref.args.length);
    ref.args.forEach((k, v) {
      _writeString(k);
      _writeValue(v);
    });
  }

  /// Write an [NdNode].
  void _writeNode(NdNode node) {
    _writeString(node.type);

    _writeVarint(node.props.length);
    node.props.forEach((k, v) {
      _writeString(k);
      _writeValue(v);
    });

    _writeVarint(node.children.length);
    for (final child in node.children) {
      _writeNode(child);
    }

    _writeVarint(node.events.length);
    node.events.forEach((name, ref) {
      _writeString(name);
      _writeActionRef(ref);
    });
  }

  /// Write an [NdComponentDef].
  void _writeComponentDef(NdComponentDef def) {
    _writeString(def.name);
    _writeVarint(def.params.length);
    for (final p in def.params) {
      _writeString(p);
    }
    _writeNode(def.body);
  }

  /// Write an [EnvelopeBody].
  void _writeBody(EnvelopeBody body) {
    _writeNode(body.root);

    _writeVarint(body.components.length);
    for (final c in body.components) {
      _writeComponentDef(c);
    }

    _writeVarint(body.data.length);
    body.data.forEach((k, v) {
      _writeString(k);
      _writeValue(v);
    });
  }

  Uint8List toBytes() => Uint8List.fromList(_buf.toBytes());
}

// ---------------------------------------------------------------------------
// Reader
// ---------------------------------------------------------------------------

class _Reader {
  final Uint8List _bytes;
  int _pos = 0;

  _Reader(this._bytes);

  /// Read a single byte.
  int _readByte() {
    if (_pos >= _bytes.length) throw StateError('Unexpected end of binary data');
    return _bytes[_pos++];
  }

  /// Read an unsigned varint (LEB128).
  int _readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = _readByte();
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  /// Read a zigzag-encoded signed varint.
  int _readSignedVarint() {
    final encoded = _readVarint();
    // Zigzag decode: (n >>> 1) ^ -(n & 1)
    return (encoded >> 1) ^ -(encoded & 1);
  }

  /// Read a length-prefixed UTF-8 string.
  String _readString() {
    final len = _readVarint();
    final sub = Uint8List.sublistView(_bytes, _pos, _pos + len);
    _pos += len;
    return utf8.decode(sub);
  }

  /// Read a tagged value.
  Object? _readValue() {
    final tag = _readByte();
    switch (tag) {
      case _tagNull:
        return null;
      case _tagArgRef:
        return NdArgRef(_readString());
      case _tagBool:
        return _readByte() != 0;
      case _tagInt:
        return _readSignedVarint();
      case _tagDouble:
        final bd =
            ByteData.sublistView(_bytes, _pos, _pos + 8);
        _pos += 8;
        return bd.getFloat64(0, Endian.little);
      case _tagString:
        return _readString();
      default:
        throw StateError('Unknown value tag: $tag');
    }
  }

  /// Read an [NdActionRef].
  NdActionRef _readActionRef() {
    final action = _readString();
    final argCount = _readVarint();
    final args = <String, Object?>{};
    for (var i = 0; i < argCount; i++) {
      final k = _readString();
      args[k] = _readValue();
    }
    return NdActionRef(action, args);
  }

  /// Read an [NdNode].
  NdNode _readNode() {
    final type = _readString();

    final propCount = _readVarint();
    final props = <String, Object?>{};
    for (var i = 0; i < propCount; i++) {
      final k = _readString();
      props[k] = _readValue();
    }

    final childCount = _readVarint();
    final children = <NdNode>[];
    for (var i = 0; i < childCount; i++) {
      children.add(_readNode());
    }

    final eventCount = _readVarint();
    final events = <String, NdActionRef>{};
    for (var i = 0; i < eventCount; i++) {
      final name = _readString();
      events[name] = _readActionRef();
    }

    return NdNode(type: type, props: props, children: children, events: events);
  }

  /// Read an [NdComponentDef].
  NdComponentDef _readComponentDef() {
    final name = _readString();
    final paramCount = _readVarint();
    final params = <String>[];
    for (var i = 0; i < paramCount; i++) {
      params.add(_readString());
    }
    final body = _readNode();
    return NdComponentDef(name: name, params: params, body: body);
  }

  /// Read an [EnvelopeBody].
  EnvelopeBody _readBody() {
    final root = _readNode();

    final componentCount = _readVarint();
    final components = <NdComponentDef>[];
    for (var i = 0; i < componentCount; i++) {
      components.add(_readComponentDef());
    }

    final dataCount = _readVarint();
    final data = <String, Object?>{};
    for (var i = 0; i < dataCount; i++) {
      final k = _readString();
      data[k] = _readValue();
    }

    return EnvelopeBody(root: root, components: components, data: data);
  }
}

// ---------------------------------------------------------------------------
// Top-level helpers (called from Writer/Reader) — module-level wrappers
// ---------------------------------------------------------------------------

void _writeBody(_Writer w, EnvelopeBody body) => w._writeBody(body);
EnvelopeBody _readBody(_Reader r) => r._readBody();
