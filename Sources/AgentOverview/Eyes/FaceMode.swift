import Foundation

/// What drives a face: a session status (panel rows), an action face (the rows below the divider)
/// or an explicit expression (playground grid).
enum FaceMode: Equatable, Sendable {
    case status(FaceStatus)
    case action(ActionFace)
    case expression(Expression)
}
