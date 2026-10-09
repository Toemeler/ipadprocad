part of 'ai_cad.dart';

/// Builds on a detached document. No live authoring is touched before all
/// native features and the independently generated Python result agree.
class Build123dNativeHistory {
  Build123dNativeHistory(this.part, this.features, this.sketches, this.body);
  final PartModel part;
  final List<PartFeature> features;
  final List<ChildSketch> sketches;
  final String body;
  void dispose() => part.dispose();
}

extension Build123dHistoryReplay on AiCad {
  Future<Build123dNativeHistory> build123dHistory(
      PartModel original, Map<String, dynamic> history,
      {required Set<String> replace,
      required Set<String> removeFeatures,
      required Set<String> removeSketches,
      String? preferredBody,
      void Function(String)? onFeature}) async {
    if (history['version'] != 1 ||
        history['nodes'] is! List ||
        (history['nodes'] as List).length > 128 ||
        history['root'] is! int) {
      throw const FormatException('Invalid editable construction history');
    }
    final p = PartModel(original.name)..loadJson(original.toJson());
    final madeFeatures = <PartFeature>[];
    final madeSketches = <ChildSketch>[];
    try {
      for (final child in original.childSketches) {
        if (removeSketches.contains(child.model.name)) continue;
        final model = SketchModel(child.model.name)
          ..geometry = [
            for (final g in child.model.geometry)
              Geo(g.type, List<double>.of(g.data),
                  layer: g.layer,
                  spline: g.spline,
                  style: g.style,
                  proj: g.proj,
                  projSeg: g.projSeg)
          ];
        model.layers.addAll(child.model.layers);
        model.eosAfter = child.model.eosAfter;
        model.hiddenLayers.addAll(child.model.hiddenLayers);
        model.lockedLayers.addAll(child.model.lockedLayers);
        model.constraints.addAll([
          for (final c in child.model.constraints)
            Constraint.fromJson(c.toJson())
        ]);
        model.userParams.addAll(child.model.userParams);
        p.childSketches.add(ChildSketch(model, child.plane, child.face,
            child.visible, child.shared, child.seq)
          ..faceRef = child.faceRef == null
              ? null
              : SketchFaceSel.fromJson(child.faceRef!.toJson())
          ..workPlaneId = child.workPlaneId);
      }
      p.features.removeWhere((f) => removeFeatures.contains(f.name));
      for (final f in p.features) {
        final source = original.features.firstWhere((s) => s.name == f.name);
        // Own every native handle independently. Staging disposal cannot
        // destroy a solid in the live document, even after a failed rebuild.
        final solid = source.solid;
        if (solid != null) {
          final shape = solid.shape
              ?.transformed(const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0]);
          if (shape == null)
            throw const FormatException(
                'Cannot stage existing native geometry');
          f.solid = KernelSolid(solid.mesh, shape.volume, shape);
          f.builtSig = source.builtSig;
        }
        if (f is DeriveFeature && source is DeriveFeature)
          f.source = source.source;
      }
      p.eopAfter = kEopAtEnd;
      applyEndOfPart(p);
      if (!recomputeAllFeatures(p, app.partKernel)) {
        throw const FormatException('Existing native history cannot rebuild');
      }
      final nodes = (history['nodes'] as List)
          .map((n) => Map<String, dynamic>.from(n as Map))
          .toList();
      double number(Object? raw) {
        if (raw is! num || !raw.isFinite || raw.abs() > 100000) {
          throw const FormatException('Invalid native history dimension');
        }
        return raw.toDouble();
      }

      ChildSketch sketch(Object? raw) {
        if (raw is! Map ||
            raw['curves'] is! List ||
            (raw['curves'] as List).isEmpty ||
            (raw['curves'] as List).length > 2000) {
          throw const FormatException('Invalid native history sketch');
        }
        final values = (raw['frame'] as List?)?.map(number).toList();
        final frame = PlaneFrame.fromFrameJson(values);
        if (frame == null ||
            (frame.u.length - 1).abs() > 1e-5 ||
            (frame.v.length - 1).abs() > 1e-5 ||
            (frame.n.length - 1).abs() > 1e-5 ||
            frame.u.dot(frame.v).abs() > 1e-5 ||
            frame.u.cross(frame.v).dot(frame.n) < .99999) {
          throw const FormatException(
              'Invalid native history sketch workplane');
        }
        final model = SketchModel(p.nextSketchName());
        model.insertLayerAboveMarker(AiCad._layerName);
        final geometry = <Geo>[];
        for (final rawCurve in raw['curves'] as List) {
          if (rawCurve is! Map || rawCurve['data'] is! List) {
            throw const FormatException('Invalid native history curve');
          }
          final type = rawCurve['type'];
          final data = (rawCurve['data'] as List).map(number).toList();
          if (!const [Geo.line, Geo.circle, Geo.arc, Geo.polyline]
                  .contains(type) ||
              (type == Geo.line && data.length != 4) ||
              (type == Geo.circle && (data.length != 3 || data[2] <= 0)) ||
              (type == Geo.arc && (data.length != 6 || data[2] <= 0)) ||
              (type == Geo.polyline &&
                  (data.length < 6 || data.length != 2 + data[1] * 2))) {
            throw const FormatException(
                'Invalid native history curve dimensions');
          }
          final spline = rawCurve['spline'] ?? 0;
          if (!const [0, Geo.splineBez].contains(spline)) {
            throw const FormatException(
                'Unsupported editable spline representation');
          }
          geometry.add(Geo(type as int, data,
              layer: AiCad._layerName, spline: spline as int));
        }
        // Native sketch geometry, constraint sidecars and solver use the
        // normal app machinery. Python owns neither a cached mesh nor a STEP.
        app.aiCommitSketch(model, geometry);
        model.dirty = true;
        final child =
            ChildSketch(model, 'face', frame, true, false, p.nextSeq());
        p.appendChildSketch(child);
        madeSketches.add(child);
        app.aiForgetRegions(model.name);
        return child;
      }

      List<ProfileSel> selections(ChildSketch child) {
        final all = app.sessionRegions(child);
        final selected = _pickRegions(
                all, const AiAction('extrude', {'regions': 'evenodd'}), 'new')
            .$1;
        if (selected == null || selected.isEmpty) {
          throw FormatException(
              'Sketch ${child.model.name} has no editable closed profile');
        }
        return [
          for (final region in selected)
            ProfileSel(regionAnchor(region).dx, regionAnchor(region).dy,
                region.outer.area)
        ];
      }

      void feature(PartFeature f) {
        f.seq = p.nextSeq();
        p.appendFeature(f);
        p.claimBodyName(f.bodyName);
        madeFeatures.add(f);
        for (final name in f.sketchNames) p.sketchByName(name)?.visible = false;
        applyEndOfPart(p);
        if (!recomputeAllFeatures(p, app.partKernel) ||
            f.computeError != null ||
            f.solid == null) {
          throw FormatException(
              'Native ${f.typeLabel} cannot rebuild: ${f.computeError ?? app.partKernel.lastError}');
        }
        onFeature?.call(f.typeLabel);
      }

      final memo = <int, String>{};
      String build(int id,
          {String? target, String output = 'new', String? preferred}) {
        if (id < 0 || id >= nodes.length || nodes[id]['id'] != id) {
          throw const FormatException('Invalid native history dependency');
        }
        if (target == null && memo.containsKey(id)) return memo[id]!;
        final node = nodes[id];
        final op = node['op'];
        int dependency(String key) {
          final value = node[key];
          if (value is! int || value >= id)
            throw const FormatException('Cyclic native history dependency');
          return value;
        }

        if (op == 'input') {
          final name = node['name'];
          if (name is! String ||
              !replace.contains(name) ||
              currentBodySolid(p, name) == null) {
            throw const FormatException(
                'Using an existing body as the base requires explicit replace; its history is preserved');
          }
          memo[id] = name;
          return name;
        }
        if (const ['join', 'cut', 'intersect'].contains(op)) {
          final left = build(dependency('left'), preferred: preferred);
          final right = dependency('right');
          if (const ['extrude', 'revolve', 'loft', 'sweep']
              .contains(nodes[right]['op'])) {
            build(right, target: left, output: op as String);
          } else {
            final tool = build(right);
            if (tool == left)
              throw const FormatException('Cannot combine a body with itself');
            feature(CombineFeature(
                name: p.nextFeatureName('Combine'),
                bodyName: left,
                tools: [tool],
                op: op as String,
                keepTool: false));
          }
          memo[id] = left;
          return left;
        }
        if (op == 'shell') {
          final body = build(dependency('left'), preferred: preferred);
          final amount = number(node['amount']);
          if (amount == 0)
            throw const FormatException('Shell thickness cannot be zero');
          final solid = currentBodySolid(p, body)!;
          final live = faceSurfaces(solid.mesh);
          final picks = <FacePick>[];
          for (final raw in node['faces'] as List) {
            final point = (raw['point'] as List).map(number).toList();
            final normal = (raw['normal'] as List).map(number).toList();
            if (point.length != 3 || normal.length != 3)
              throw const FormatException('Invalid shell opening');
            final at = Vec3(point[0], point[1], point[2]);
            final dir = Vec3(normal[0], normal[1], normal[2]);
            final matched = live
                .where((f) =>
                    (f.centroid - at).length < 0.05 && f.d.dot(dir) > .999)
                .toList();
            if (matched.length != 1)
              throw const FormatException(
                  'Native shell opening differs from Python');
            final face = matched.single;
            picks.add(FacePick(
                face.centroid.x,
                face.centroid.y,
                face.centroid.z,
                face.d.x,
                face.d.y,
                face.d.z,
                face.area,
                face.type));
          }
          feature(ShellFeature(
              name: p.nextFeatureName('Shell'),
              bodyName: body,
              faces: picks,
              thickness: amount.abs(),
              outward: amount > 0));
          memo[id] = body;
          return body;
        }
        if (op == 'fillet' || op == 'chamfer') {
          final body = build(dependency('left'), preferred: preferred);
          final solid = currentBodySolid(p, body)!;
          final points = node['edges'];
          if (points is! List || points.isEmpty || points.length > 32) {
            throw const FormatException('Invalid native finishing edges');
          }
          final picked = _selectEdges(app.partKernel.edgesOf(solid),
              AiAction(op as String, {'near': points}), solid.mesh);
          if (picked.length != points.length) {
            throw const FormatException(
                'Native finishing edge selection differs from Python');
          }
          final edges = [
            for (final e in picked)
              EdgeSel(e.mx, e.my, e.mz, e.length, e.kind, e.radius)
          ];
          final size = number(node['size']);
          feature(op == 'fillet'
              ? FilletFeature(
                  name: p.nextFeatureName('Fillet'),
                  bodyName: body,
                  edges: edges,
                  radii: [for (final _ in edges) size],
                  exprRadius: '$size mm')
              : ChamferFeature(
                  name: p.nextFeatureName('Chamfer'),
                  bodyName: body,
                  edges: edges,
                  distance1: size,
                  distance2: size,
                  exprD1: '$size mm',
                  exprD2: '$size mm'));
          memo[id] = body;
          return body;
        }
        final rawProfiles = node['profiles'];
        if (rawProfiles is! List ||
            rawProfiles.isEmpty ||
            rawProfiles.length > 20) {
          throw const FormatException(
              'Native feature requires sketch profiles');
        }
        final profiles = [for (final raw in rawProfiles) sketch(raw)];
        final body = target ?? preferred ?? p.nextSolidName();
        PartFeature f;
        if (op == 'extrude') {
          if (profiles.length != 1)
            throw const FormatException('Extrude requires one profile sketch');
          final amount = number(node['amount']);
          if (amount == 0)
            throw const FormatException('Extrude amount cannot be zero');
          final direction = node['both'] == true
              ? ExtrudeDirection.symmetric
              : amount < 0
                  ? ExtrudeDirection.flipped
                  : ExtrudeDirection.defaultDir;
          final taper = -number(node['taper']);
          f = ExtrudeFeature(
              name: p.nextFeatureName(),
              bodyName: body,
              sketchName: profiles.single.model.name,
              profiles: selections(profiles.single),
              direction: direction,
              distanceA: node['both'] == true ? 2 * amount.abs() : amount.abs(),
              distanceB: node['both'] == true ? amount.abs() : 0,
              taperDeg: taper,
              exprA:
                  '${node['both'] == true ? 2 * amount.abs() : amount.abs()} mm',
              exprB: '${amount.abs()} mm',
              exprTaper: '$taper deg',
              output: output);
        } else if (op == 'revolve') {
          final ax = (node['axis'] as List).map(number).toList();
          if (ax.length != 4 || ax[2] * ax[2] + ax[3] * ax[3] < 1e-10) {
            throw const FormatException('Invalid native revolution axis');
          }
          final angle = number(node['angle']);
          if (angle == 0 || angle.abs() > 360)
            throw const FormatException('Invalid native revolution angle');
          f = RevolveFeature(
              name: p.nextFeatureName('Revolution'),
              bodyName: body,
              sketchName: profiles.single.model.name,
              profiles: selections(profiles.single),
              axPx: ax[0],
              axPy: ax[1],
              axDx: ax[2],
              axDy: ax[3],
              angleA: angle.abs(),
              direction: angle < 0
                  ? ExtrudeDirection.flipped
                  : ExtrudeDirection.defaultDir,
              full: angle.abs() == 360,
              exprA: '${angle.abs()} deg',
              output: output);
        } else if (op == 'loft') {
          if (profiles.length < 2)
            throw const FormatException('Loft requires two or more sections');
          f = LoftFeature(
              name: p.nextFeatureName('Loft'),
              bodyName: body,
              sectionSketches: [for (final s in profiles) s.model.name],
              sections: [for (final s in profiles) selections(s).single],
              solidOutput: true,
              ruled: node['ruled'] == true,
              output: output);
        } else if (op == 'sweep') {
          final path = sketch(node['path']);
          _joinPathChain(path);
          final curve = _pathCurve(path);
          if (curve == null)
            throw const FormatException('Sweep requires an editable open path');
          f = SweepFeature(
              name: p.nextFeatureName('Sweep'),
              bodyName: body,
              sketchName: profiles.single.model.name,
              profiles: selections(profiles.single),
              path: curve,
              output: output);
        } else {
          throw FormatException('No editable native feature for $op');
        }
        feature(f);
        memo[id] = body;
        return body;
      }

      final body = build(history['root'] as int, preferred: preferredBody);
      if (madeFeatures.isEmpty)
        throw const FormatException(
            'Python produced no new editable modelling features');
      return Build123dNativeHistory(p, madeFeatures, madeSketches, body);
    } catch (_) {
      p.dispose();
      rethrow;
    }
  }
}
