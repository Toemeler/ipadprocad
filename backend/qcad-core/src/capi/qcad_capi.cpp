/*
 * iPadProCAD — C-ABI wrapper implementation around the headless QCAD core.
 * Milestone M2. See qcad_capi.h for the contract.
 *
 * This translation unit is the ONLY place C++/Qt/QCAD types are used; the
 * public surface (qcad_capi.h) is plain C. Consumed by a C smoke test on Linux
 * and (later) by Dart FFI on iOS.
 */
#include "qcad_capi.h"

#include <algorithm>
#include <cstring>
#include <string>

#include <QtGlobal>
#include <QCoreApplication>
#include <QString>
#include <QSharedPointer>
#include <QSet>
#include <QVariantMap>

/* Core / storage / transaction / geometry */
#include "RDocument.h"
#include "RMemoryStorage.h"
#include "RSpatialIndexSimple.h"
#include "RTransaction.h"
#include "RBox.h"
#include "RVector.h"

/* Entity data classes we construct directly */
#include "RLayer.h"
#include "RLineData.h"
#include "RCircleData.h"
#include "RArcData.h"
#include "RPolylineData.h"

/* DXF import / export */
#include "RDxfImporter.h"
#include "RDxfExporter.h"

/* Property-type registration headers (generated) */
#include "RObject.h"
#include "REntity.h"
#include "RArcEntity.h"
#include "RAttributeDefinitionEntity.h"
#include "RAttributeEntity.h"
#include "RBlock.h"
#include "RBlockReferenceEntity.h"
#include "RCircleEntity.h"
#include "RColor.h"
#include "RDimAlignedEntity.h"
#include "RDimAngular2LEntity.h"
#include "RDimAngular3PEntity.h"
#include "RDimAngularEntity.h"
#include "RDimArcLengthEntity.h"
#include "RDimDiametricEntity.h"
#include "RDimLinearEntity.h"
#include "RDimOrdinateEntity.h"
#include "RDimRadialEntity.h"
#include "RDimRotatedEntity.h"
#include "RDimStyle.h"
#include "RDimStyleData.h"
#include "RDimensionEntity.h"
#include "RDocumentVariables.h"
#include "REllipseEntity.h"
#include "RFaceEntity.h"
#include "RHatchEntity.h"
#include "RImageEntity.h"
#include "RLayer.h"
#include "RLayerState.h"
#include "RLayout.h"
#include "RLeaderEntity.h"
#include "RLineEntity.h"
#include "RLinetype.h"
#include "RLineweight.h"
#include "RPointEntity.h"
#include "RPolylineEntity.h"
#include "RRayEntity.h"
#include "RSolidEntity.h"
#include "RSplineEntity.h"
#include "RTextBasedEntity.h"
#include "RTextEntity.h"
#include "RToleranceEntity.h"
#include "RTraceEntity.h"
#include "RUcs.h"
#include "RView.h"
#include "RViewportEntity.h"
#include "RWipeoutEntity.h"
#include "RXLineEntity.h"

namespace {

bool g_initialised = false;

/* Ensure a QCoreApplication exists so Qt (QSettings/paths) is usable headless.
 * Intentionally leaked: it must outlive every later Qt call. No-op if the host
 * already created one (e.g. a future GUI build). */
void ensureApp() {
    if (QCoreApplication::instance() == nullptr) {
        static int argc = 1;
        static char arg0[] = "ipadprocad";
        static char *argv[] = { arg0, nullptr };
        new QCoreApplication(argc, argv);
    }
    // RSettings::isInitialized() is true iff the organization name is non-empty.
    // Set names (only if the host has not) so QCAD's settings layer works and
    // stops logging "RSettings not initialized". Reads simply return defaults.
    if (QCoreApplication::organizationName().isEmpty()) {
        QCoreApplication::setOrganizationName(QStringLiteral("iPadProCAD"));
    }
    if (QCoreApplication::applicationName().isEmpty()) {
        QCoreApplication::setApplicationName(QStringLiteral("iPadProCAD"));
    }
}

} // namespace

/* Opaque handle definition. Members are declared in construction order:
 * storage and spatialIndex must exist before RDocument binds references. */
struct qcad_document {
    RMemoryStorage *storage;
    RSpatialIndexSimple *spatialIndex;
    RDocument *doc;
    /* Layer that qcad_add_* assigns to. "0" is the layer RDocument::init()
     * always creates, so an untouched document still produces valid DXF. */
    QString currentLayer = QString("0");
    qcad_document()
        : storage(new RMemoryStorage()),
          spatialIndex(new RSpatialIndexSimple()),
          doc(new RDocument(*storage, *spatialIndex)) {
        // RDocument's constructor already calls init(). storage and
        // spatialIndex derive from RRequireHeap and are owned by RDocument:
        // ~RDocument deletes them via doDelete() (delete this), so we must NOT
        // delete them here or they would be freed twice.
    }
    ~qcad_document() {
        delete doc;
    }
};

extern "C" {

void qcad_init(void) {
    if (g_initialised) {
        return;
    }
    ensureApp();
    /* Register property types. Base classes first, then concrete types
     * (generated from the set of classes exposing a static init()). */
    RObject::init();
    REntity::init();
    RArcEntity::init();
    RAttributeDefinitionEntity::init();
    RAttributeEntity::init();
    RBlock::init();
    RBlockReferenceEntity::init();
    RCircleEntity::init();
    RDimAlignedEntity::init();
    RDimAngular2LEntity::init();
    RDimAngular3PEntity::init();
    RDimAngularEntity::init();
    RDimArcLengthEntity::init();
    RDimDiametricEntity::init();
    RDimLinearEntity::init();
    RDimOrdinateEntity::init();
    RDimRadialEntity::init();
    RDimRotatedEntity::init();
    RDimStyle::init();
    RDimStyleData::init();
    RDimensionEntity::init();
    RDocumentVariables::init();
    REllipseEntity::init();
    RFaceEntity::init();
    RHatchEntity::init();
    RImageEntity::init();
    RLayer::init();
    RLayerState::init();
    RLayout::init();
    RLeaderEntity::init();
    RLineEntity::init();
    RLinetype::init();
    RPointEntity::init();
    RPolylineEntity::init();
    RRayEntity::init();
    RSolidEntity::init();
    RSplineEntity::init();
    RTextBasedEntity::init();
    RTextEntity::init();
    RToleranceEntity::init();
    RTraceEntity::init();
    RUcs::init();
    RView::init();
    RViewportEntity::init();
    RWipeoutEntity::init();
    RXLineEntity::init();
    g_initialised = true;
}

const char *qcad_version(void) {
    static const std::string v =
        std::string("iPadProCAD C-API 0.1.0 (Qt ") + QT_VERSION_STR + ")";
    return v.c_str();
}

qcad_document *qcad_document_new(void) {
    try {
        return new qcad_document();
    } catch (...) {
        return nullptr;
    }
}

void qcad_document_free(qcad_document *doc) {
    delete doc;
}

/* Layer id for [name], creating the layer if needed. INVALID_ID on failure. */
static RObject::Id ensureLayer(qcad_document *doc, const QString &name) {
    if (doc == nullptr || name.isEmpty()) {
        return RObject::INVALID_ID;
    }
    RObject::Id id = doc->doc->getLayerId(name);
    if (id != RObject::INVALID_ID) {
        return id;
    }
    QSharedPointer<RObject> layer(new RLayer(doc->doc, name));
    RTransaction t(doc->doc->getStorage(), "add layer", true);
    t.addObject(layer);
    t.end();
    return doc->doc->getLayerId(name);
}

static bool addEntity(qcad_document *doc, QSharedPointer<RObject> obj) {
    if (doc == nullptr || obj.isNull()) {
        return false;
    }
    /* Bind the entity to the current layer BEFORE it goes into the storage —
     * this is the whole point: geometry that is not on a layer cannot be shown,
     * hidden or exported as a layer. */
    QSharedPointer<REntity> e = obj.dynamicCast<REntity>();
    if (!e.isNull()) {
        const RObject::Id lid = ensureLayer(doc, doc->currentLayer);
        if (lid != RObject::INVALID_ID) {
            e->setLayerId(lid);
        }
    }
    RTransaction t(doc->doc->getStorage(), "add entity", true);
    t.addObject(obj);
    t.end();
    return true;
}

int qcad_layer_add(qcad_document *doc, const char *name) {
    if (doc == nullptr || name == nullptr) {
        return 0;
    }
    return ensureLayer(doc, QString::fromUtf8(name)) != RObject::INVALID_ID
        ? 1 : 0;
}

int qcad_set_current_layer(qcad_document *doc, const char *name) {
    if (doc == nullptr || name == nullptr) {
        return 0;
    }
    const QString n = QString::fromUtf8(name);
    const RObject::Id lid = ensureLayer(doc, n);
    if (lid == RObject::INVALID_ID) {
        return 0;
    }
    doc->currentLayer = n;
    /* Make it the DOCUMENT's current layer too. When a new entity is stored,
     * RTransaction stamps it with doc->getCurrentLayerId() and that OVERRIDES
     * any layer set on the entity beforehand (RTransaction.cpp: "place entity
     * on current layer"). Without this the document's current layer stays "0",
     * so every entity lands on "0" no matter what qcad_set_current_layer or
     * setLayerId did — which is exactly the "everything goes to layer 0" bug. */
    doc->doc->setCurrentLayer(lid);
    return 1;
}

int qcad_entity_layer(const qcad_document *doc, long long id,
                      char *out, int max) {
    if (doc == nullptr || out == nullptr || max <= 0) {
        return 0;
    }
    QSharedPointer<REntity> e =
        doc->doc->queryEntity(static_cast<REntity::Id>(id));
    if (e.isNull()) {
        return 0;
    }
    const QByteArray n = doc->doc->getLayerName(e->getLayerId()).toUtf8();
    const int len = n.size();
    if (len + 1 > max) {
        return 0;
    }
    std::memcpy(out, n.constData(), static_cast<size_t>(len));
    out[len] = '\0';
    return 1;
}

int qcad_add_line(qcad_document *doc, double x1, double y1, double x2, double y2) {
    if (doc == nullptr) {
        return 0;
    }
    QSharedPointer<RObject> e(
        new RLineEntity(doc->doc, RLineData(RVector(x1, y1), RVector(x2, y2))));
    return addEntity(doc, e) ? 1 : 0;
}

int qcad_add_circle(qcad_document *doc, double cx, double cy, double radius) {
    if (doc == nullptr) {
        return 0;
    }
    QSharedPointer<RObject> e(
        new RCircleEntity(doc->doc, RCircleData(RVector(cx, cy), radius)));
    return addEntity(doc, e) ? 1 : 0;
}

int qcad_add_arc(qcad_document *doc, double cx, double cy, double radius,
                 double start_angle, double end_angle, int reversed) {
    if (doc == nullptr) {
        return 0;
    }
    QSharedPointer<RObject> e(new RArcEntity(
        doc->doc,
        RArcData(RVector(cx, cy), radius, start_angle, end_angle, reversed != 0)));
    return addEntity(doc, e) ? 1 : 0;
}

int qcad_add_polyline(qcad_document *doc, const double *pts, size_t count,
                      int closed) {
    if (doc == nullptr || (count > 0 && pts == nullptr)) {
        return 0;
    }
    RPolylineData data;
    for (size_t i = 0; i < count; ++i) {
        data.appendVertex(RVector(pts[2 * i], pts[2 * i + 1]));
    }
    data.setClosed(closed != 0);
    QSharedPointer<RObject> e(new RPolylineEntity(doc->doc, data));
    return addEntity(doc, e) ? 1 : 0;
}

int qcad_entity_count(const qcad_document *doc) {
    if (doc == nullptr) {
        return -1;
    }
    return static_cast<int>(doc->doc->queryAllEntities().size());
}

int qcad_bounding_box(const qcad_document *doc, double *out_minx,
                      double *out_miny, double *out_maxx, double *out_maxy) {
    if (doc == nullptr) {
        return 0;
    }
    RBox box = doc->doc->getBoundingBox(true, false);
    if (!box.isValid()) {
        return 0;
    }
    const RVector mn = box.getMinimum();
    const RVector mx = box.getMaximum();
    if (out_minx) *out_minx = mn.x;
    if (out_miny) *out_miny = mn.y;
    if (out_maxx) *out_maxx = mx.x;
    if (out_maxy) *out_maxy = mx.y;
    return 1;
}

int qcad_entity_ids(const qcad_document *doc, long long *out_ids, int max) {
    if (doc == nullptr || (max > 0 && out_ids == nullptr)) {
        return -1;
    }
    QSet<REntity::Id> ids = doc->doc->queryAllEntities();
    QList<REntity::Id> sorted(ids.begin(), ids.end());
    std::sort(sorted.begin(), sorted.end());
    const int total = static_cast<int>(sorted.size());
    const int n = qMin(total, max);
    for (int i = 0; i < n; ++i) {
        out_ids[i] = static_cast<long long>(sorted.at(i));
    }
    return total;
}

int qcad_entity_geometry(const qcad_document *doc, long long id,
                         int *out_type, double *out_data, int max_doubles) {
    if (doc == nullptr || out_type == nullptr ||
        (max_doubles > 0 && out_data == nullptr)) {
        return -1;
    }
    QSharedPointer<REntity> e =
        doc->doc->queryEntity(static_cast<REntity::Id>(id));
    if (e.isNull()) {
        return -1;
    }
    *out_type = 0;
    /* Local staging buffer for the fixed-size types; polyline streams. */
    auto put = [&](int i, double v) {
        if (out_data != nullptr && i < max_doubles) {
            out_data[i] = v;
        }
    };
    switch (e->getType()) {
    case RS::EntityLine: {
        QSharedPointer<RLineEntity> l = e.dynamicCast<RLineEntity>();
        if (l.isNull()) return -1;
        const RLineData &d = l->getData();
        *out_type = 1;
        put(0, d.getStartPoint().x); put(1, d.getStartPoint().y);
        put(2, d.getEndPoint().x);   put(3, d.getEndPoint().y);
        return 4;
    }
    case RS::EntityCircle: {
        QSharedPointer<RCircleEntity> c = e.dynamicCast<RCircleEntity>();
        if (c.isNull()) return -1;
        const RCircleData &d = c->getData();
        *out_type = 2;
        put(0, d.getCenter().x); put(1, d.getCenter().y); put(2, d.getRadius());
        return 3;
    }
    case RS::EntityArc: {
        QSharedPointer<RArcEntity> a = e.dynamicCast<RArcEntity>();
        if (a.isNull()) return -1;
        const RArcData &d = a->getData();
        *out_type = 3;
        put(0, d.getCenter().x); put(1, d.getCenter().y); put(2, d.getRadius());
        put(3, d.getStartAngle()); put(4, d.getEndAngle());
        put(5, d.isReversed() ? 1.0 : 0.0);
        return 6;
    }
    case RS::EntityPolyline: {
        QSharedPointer<RPolylineEntity> p = e.dynamicCast<RPolylineEntity>();
        if (p.isNull()) return -1;
        const RPolylineData &d = p->getData();
        const QList<RVector> verts = d.getVertices();
        *out_type = 4;
        put(0, d.isClosed() ? 1.0 : 0.0);
        put(1, static_cast<double>(verts.size()));
        for (int i = 0; i < verts.size(); ++i) {
            put(2 + 2 * i, verts.at(i).x);
            put(3 + 2 * i, verts.at(i).y);
        }
        return 2 + 2 * static_cast<int>(verts.size());
    }
    default:
        *out_type = 0;
        return 0;
    }
}

int qcad_load_dxf(qcad_document *doc, const char *path) {
    if (doc == nullptr || path == nullptr) {
        return 0;
    }
    RDxfImporter importer(*doc->doc);
    return importer.importFile(QString::fromUtf8(path), QString()) ? 1 : 0;
}

int qcad_save_dxf(qcad_document *doc, const char *path, const char *version) {
    if (doc == nullptr || path == nullptr) {
        return 0;
    }
    QString nameFilter; /* empty -> exporter default (R2000/AC1015) */
    if (version != nullptr && version[0] != '\0') {
        const QString v = QString::fromUtf8(version);
        if (v.compare("R12", Qt::CaseInsensitive) == 0) {
            nameFilter = "R12";
        } else if (v.compare("min", Qt::CaseInsensitive) == 0) {
            nameFilter = "min";
        }
    }
    RDxfExporter exporter(*doc->doc);
    return exporter.exportFile(QString::fromUtf8(path), nameFilter, true) ? 1 : 0;
}

} /* extern "C" */
