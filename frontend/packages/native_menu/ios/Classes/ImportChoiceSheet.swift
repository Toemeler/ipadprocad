// The question that has to be asked before a mesh import, asked natively.
//
// WHY THIS IS A DIALOG AT ALL
// ---------------------------
// A downloaded STL is triangles, and there are two honest things to do with
// it, which are not versions of each other:
//
//   convert  — reverse-engineer surfaces, so the model has FACES: a cylinder
//              is a cylinder you can fillet, offset and dimension. It takes
//              seconds to a minute and it is a reconstruction, so it can get
//              a detail wrong.
//   triangles— keep the mesh exactly, one B-Rep face per triangle. Instant to
//              decide, faithful to the last vertex, and almost nothing in a
//              CAD sense can be done to it afterwards.
//
// Neither is the right default for everyone, and guessing produces the worst
// outcome of the two: a user who wanted a faithful copy waiting a minute for
// an approximation, or a user who wanted editable geometry getting 80,000
// faces. So ask, once, at the point of import.
//
// WHY UIKIT AND NOT FLUTTER
// -------------------------
// The same reason as BusyOverlay: this dialog is the last thing on screen
// before a blocking native call, and the busy card that replaces it is UIKit.
// Presenting one from Flutter and the other from UIKit puts the dismissal of
// the first and the appearance of the second on two different threads with no
// ordering between them, and the gap shows. Both native means the sheet's
// dismissal completion is where the card goes up: no gap, no double-tap
// getting through, and the whole exchange survives a frozen UI thread.
import Flutter
import UIKit

enum ImportChoiceSheet {
    /// Asks how to bring a mesh in. `reply` is called exactly once, with
    /// "convert", "faceted", or nil for cancelled / could not present.
    ///
    /// An ALERT, not an action sheet, for two reasons that both come from
    /// where this is asked. First, the import starts from the Files picker, so
    /// by the time this appears there is no button, cell or toolbar item it
    /// belongs to — and on iPad an action sheet is a popover that must point
    /// at something. An alert is centred by design and needs no anchor.
    /// Second, each choice needs a sentence to distinguish it, and an alert
    /// has a message body to put them in; three actions make UIKit stack them
    /// vertically, which is the layout this wants anyway.
    static func make(
        title: String,
        message: String?,
        convertLabel: String,
        convertDetail: String,
        facetedLabel: String?,
        facetedDetail: String,
        cancelLabel: String,
        reply: @escaping (String?) -> Void
    ) -> UIAlertController {
        // A nil facetedLabel means the 1:1 path cannot take this mesh — it is
        // over the per-triangle face limit and the kernel would refuse it.
        // Offering a button that is going to fail is worse than not offering
        // it, so the caller sends the reason as `facetedDetail` instead and
        // the action is left out. See kMaxFacetedTriangles.
        let offerFaceted = !(facetedLabel ?? "").isEmpty

        // Details belong under their own choice, and UIAlertAction has no
        // subtitle. Putting them in the message is what is left; the blank
        // line is what stops the two descriptions running together.
        var body = message ?? ""
        if !convertDetail.isEmpty || !facetedDetail.isEmpty {
            if !body.isEmpty { body += "\n\n" }
            body += "\(convertLabel) — \(convertDetail)"
            if !facetedDetail.isEmpty {
                body += "\n\n"
                body += offerFaceted
                    ? "\(facetedLabel ?? "") — \(facetedDetail)"
                    : facetedDetail
            }
        }
        let sheet = UIAlertController(
            title: title.isEmpty ? nil : title,
            message: body.isEmpty ? nil : body,
            preferredStyle: .alert)

        // A FlutterResult must fire exactly once. Two taps land before the
        // dismissal animation finishes, and a second reply crashes the engine.
        var answered = false
        let once: (String?) -> Void = { value in
            if answered { return }
            answered = true
            reply(value)
        }

        // No glyphs. The `setValue(_:forKey: "image")` trick works on an
        // action sheet's rows and is ignored on an alert's, so adding them
        // here would be code that reads as if it did something.
        let convert = UIAlertAction(title: convertLabel, style: .default) { _ in
            once("convert")
        }
        sheet.addAction(convert)
        if offerFaceted, let label = facetedLabel {
            sheet.addAction(UIAlertAction(title: label, style: .default) { _ in
                once("faceted")
            })
        }
        sheet.addAction(UIAlertAction(title: cancelLabel, style: .cancel) { _ in
            once(nil)
        })
        // What a hardware Return lands on, and what UIKit draws in bold.
        // Meaningful on an alert; it is ignored on an action sheet.
        sheet.preferredAction = convert
        return sheet
    }
}
