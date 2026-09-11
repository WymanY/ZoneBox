import AppKit
import ZoneBoxCore

struct WorkspaceCapturePromptContext: Equatable {
    /// Connected displays that currently hold at least one saveable window.
    var contentDisplayCount: Int
    /// The pointer's display, the same "this display" layout assignment uses.
    var thisDisplayID: DisplayIdentity.ID?
    var thisDisplayName: String

    /// A scope choice only exists when more than one display would be saved.
    var offersDisplayChoice: Bool {
        contentDisplayCount >= 2 && thisDisplayID != nil
    }
}

struct WorkspaceCaptureRequest: Equatable {
    var name: String
    /// nil saves every display that holds windows.
    var displayID: DisplayIdentity.ID?
}

/// Preview of what a save would record, for the whole desk and optionally the
/// pointer's display alone. Feeds the switcher's naming step.
struct WorkspaceCaptureSummary: Equatable {
    struct DisplayScope: Equatable {
        var id: DisplayIdentity.ID
        var name: String
        var applicationCount: Int
        var suggestedName: String
    }

    var applicationCount: Int
    var displayCount: Int
    var suggestedName: String
    /// Present only when a scope choice is offered (see
    /// `WorkspaceCapturePromptContext.offersDisplayChoice`).
    var thisDisplay: DisplayScope?

    var switcherDisplayChoice: WorkspaceSwitcherDisplayChoice? {
        thisDisplay.map {
            WorkspaceSwitcherDisplayChoice(
                displayID: $0.id,
                suggestedName: $0.suggestedName,
                captureCount: $0.applicationCount
            )
        }
    }
}

/// Modal "Save Workspace" prompt shared by the console and the fallback menu.
/// Paths without UI always save every display; this prompt is the one place a
/// new workspace can be narrowed to the pointer's display.
@MainActor
final class WorkspaceCapturePrompt: NSObject {
    private let context: WorkspaceCapturePromptContext
    private let suggestedName: (DisplayIdentity.ID?) -> String
    private let field = NSTextField(string: "")
    private var checkbox: NSButton?
    private var lastSuggestion = ""

    init(
        context: WorkspaceCapturePromptContext,
        suggestedName: @escaping (DisplayIdentity.ID?) -> String
    ) {
        self.context = context
        self.suggestedName = suggestedName
        super.init()
    }

    func run() -> WorkspaceCaptureRequest? {
        let alert = NSAlert()
        alert.messageText = L10n.text(.workspaceNameTitle)
        alert.informativeText = L10n.text(.workspaceNameMessage)
        lastSuggestion = suggestedName(nil)
        field.stringValue = lastSuggestion
        field.placeholderString = L10n.text(.workspaceNamePlaceholder)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = makeAccessoryView()
        alert.addButton(withTitle: L10n.text(.workspaceSave))
        alert.addButton(withTitle: L10n.text(.editorCancel))
        alert.window.initialFirstResponder = field
        if !field.stringValue.isEmpty {
            field.selectText(nil)
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return WorkspaceCaptureRequest(name: field.stringValue, displayID: selectedDisplayID)
    }

    private var selectedDisplayID: DisplayIdentity.ID? {
        checkbox?.state == .on ? context.thisDisplayID : nil
    }

    private func makeAccessoryView() -> NSView {
        guard context.offersDisplayChoice else { return field }
        let checkbox = NSButton(
            checkboxWithTitle: String(
                format: L10n.text(.workspaceCaptureThisDisplayOnly),
                context.thisDisplayName
            ),
            target: self,
            action: #selector(scopeChanged(_:))
        )
        checkbox.state = .off
        checkbox.sizeToFit()
        checkbox.frame = NSRect(x: 0, y: 0, width: field.frame.width, height: checkbox.frame.height)
        let spacing: CGFloat = 8
        let container = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: field.frame.width,
                height: field.frame.height + spacing + checkbox.frame.height
            )
        )
        field.frame.origin = NSPoint(x: 0, y: checkbox.frame.height + spacing)
        container.addSubview(field)
        container.addSubview(checkbox)
        self.checkbox = checkbox
        return container
    }

    /// The suggested name lists only apps inside the chosen scope. A name the
    /// user typed is left alone.
    @objc
    private func scopeChanged(_ sender: NSButton) {
        guard field.stringValue == lastSuggestion else { return }
        lastSuggestion = suggestedName(selectedDisplayID)
        field.stringValue = lastSuggestion
    }
}
