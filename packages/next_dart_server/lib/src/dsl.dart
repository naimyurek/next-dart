import 'package:next_dart_protocol/next_dart_protocol.dart';

/// Text widget. [text] is a String literal or an [NdArgRef] (in component bodies).
NdNode ndText(Object text) => NdNode(type: 'Text', props: {'text': text});

/// Vertical layout.
NdNode ndColumn(List<NdNode> children) => NdNode(type: 'Column', children: children);

/// Single-child card. The card node adopts the child's children directly,
/// so the card acts as a layout container. Use [ndColumn]/[ndPadding] inside
/// to compose multiple children under a Card.
NdNode ndCard({required NdNode child}) =>
    NdNode(type: 'Card', props: child.props, children: child.children, events: child.events);

/// Single-child padding (uniform).
NdNode ndPadding({required double all, required NdNode child}) =>
    NdNode(type: 'Padding', props: {'all': all}, children: [child]);

/// Network image.
NdNode ndImage(Object src) => NdNode(type: 'Image', props: {'src': src});

/// Button with a single tap action.
NdNode ndButton({required Object label, required NdActionRef onPressed}) =>
    NdNode(type: 'Button', props: {'label': label}, events: {'onPressed': onPressed});

/// Reference a server/client action with optional args.
NdActionRef action(String id, [Map<String, Object?> args = const {}]) =>
    NdActionRef(id, args);

/// Reference a composite-component parameter (only valid inside a component body).
NdArgRef ndArg(String name) => NdArgRef(name);

/// Instantiate a composite component [name] with literal [props].
NdNode ndUse(String name, Map<String, Object?> props) =>
    NdNode(type: name, props: props);
