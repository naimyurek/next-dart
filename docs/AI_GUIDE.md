# Authoring next-dart pages (for AI agents)

A page is a Dart function on the backend that returns a widget tree built from
the DSL in `package:next_dart_server`. The framework signs, encrypts, versions,
and serves it as a neutral JSON tree; the Flutter client renders it. You only
write backend Dart.

## Primitives

All primitives live in `package:next_dart_server/src/dsl.dart` and are
re-exported from `package:next_dart_server/next_dart_server.dart`.

| Function | Signature | Notes |
|---|---|---|
| `ndText` | `ndText(Object text)` | text is a `String` literal or an `NdArgRef` (inside a component body) |
| `ndColumn` | `ndColumn(List<NdNode> children)` | vertical layout |
| `ndCard` | `ndCard({required NdNode child})` | single-child card surface |
| `ndPadding` | `ndPadding({required double all, required NdNode child})` | uniform padding |
| `ndImage` | `ndImage(Object src)` | network image; `src` is a URL string or an `NdArgRef` |
| `ndButton` | `ndButton({required Object label, required NdActionRef onPressed})` | label is a `String` or an `NdArgRef` |

### Quick example — a counter page

```dart
// In your page builder (PageContext ctx):
final count = ctx.state.get<int>('count', 0);
return ndColumn([
  ndText('Count: $count'),
  ndButton(label: 'Increment', onPressed: action('inc')),
]);
```

## Actions

`action(String id, [Map<String, Object?> args = const {}])` produces an
`NdActionRef`. It is only used as the value of `onPressed` (or another event
prop). Register the handler on your `NextDartApp`:

```dart
app.action('inc', (ctx) {
  ctx.state.update<int>('count', 0, (n) => n + 1);
});
```

After any action handler runs the page is rebuilt and the updated tree is
re-sent to the client automatically.

Pass extra data with args:

```dart
ndButton(label: 'Buy', onPressed: action('buy', {'id': 7}))

app.action('buy', (ctx) {
  ctx.state.set('bought', '${ctx.args['id']}');
});
```

## Composite components

A composite component is defined on the server from catalog primitives and
shipped as data inside the envelope. Adding or changing one requires **no
Flutter app rebuild**.

### Define with `ndComponent`

```dart
// packages/next_dart_server/src/component_dsl.dart
final productCard = ndComponent('ProductCard', ['title', 'price', 'id'], (a) {
  return ndCard(
    child: ndColumn([
      ndText(a('title')),    // a('x') returns NdArgRef('x')
      ndText(a('price')),
      ndButton(label: 'Buy', onPressed: action('buy', {'id': a('id')})),
    ]),
  );
});
```

Register the component when building your `NextDartApp`:

```dart
final app = NextDartApp(
  signingKeyPair: kp,
  secretKey: secret,
  keyId: 'demo',
  components: [productCard],   // <-- pass list of NdComponentDef
);
```

### Use with `ndUse`

```dart
// In a page builder:
ndUse('ProductCard', {'title': 'Running Shoe', 'price': r'$79', 'id': 7})
```

`ndUse(String name, Map<String, Object?> props)` produces an `NdNode` whose
`type` matches the component name. The renderer resolves it against the
component catalog at render time.

## Wire format (JSON Schema)

Every node serialises to:

```json
{
  "type": "Column",
  "props":    { "label": "Buy" },
  "children": [ /* NdNode */ ],
  "events":   { "onPressed": { "action": "inc", "args": {} } }
}
```

Fields that are empty (`props: {}`, `children: []`, `events: {}`) are **omitted**
from the wire. An `argRef` appears in `props` or action `args` as:

```json
{ "$arg": "title" }
```

The full JSON Schema is at `docs/next_dart_tree.schema.json`.

## Rules

- Only widgets in the client catalog (the six primitives above) or composite
  components composed from them can be used. A genuinely new *native* widget
  (e.g. a map view) requires a client update to register a new catalog entry.
- `a('param')` / `NdArgRef` is **only valid inside** an `ndComponent` builder.
  Using it in a page builder directly will cause a type error at runtime.
- Composite components may be nested: an `ndComponent` body can use `ndUse` to
  reference another composite component.
- All state lives in `ctx.state` (`PageContext.state` / `ActionContext.state`).
  In the MVP this is per-process; Phase 2 will key it per session token.

## Complete working example

See `examples/counter_app/server/lib/app.dart` for the full counter + product
card demo that exercises all primitives, an action with args, and a composite
component.
