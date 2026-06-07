import 'package:next_dart_protocol/next_dart_protocol.dart';

/// Build a composite component. The builder receives an `a` function that
/// produces an [NdArgRef] for a declared param, e.g. `a('title')`.
NdComponentDef ndComponent(
  String name,
  List<String> params,
  NdNode Function(NdArgRef Function(String)) build,
) {
  return NdComponentDef(
    name: name,
    params: params,
    body: build((p) {
      assert(params.contains(p), 'unknown param "$p" in component "$name"');
      return NdArgRef(p);
    }),
  );
}
