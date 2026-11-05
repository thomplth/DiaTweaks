import AppKit

private func unwrapped(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    return mirror.children.first.flatMap { unwrapped($0.value) }
}

private func field(_ value: Any?, _ path: String) -> Any? {
    var current = value
    for label in path.split(separator: ".") {
        guard let holder = current.flatMap(unwrapped) else { return nil }
        var mirror: Mirror? = Mirror(reflecting: holder)
        current = nil
        while let level = mirror, current == nil {
            current = level.children.first { $0.label == String(label) }?.value
            mirror = level.superclassMirror
        }
    }
    return current.flatMap(unwrapped)
}

private func entries(_ collection: Any?) -> [Any] {
    guard let collection = collection.flatMap(unwrapped) else { return [] }
    return Mirror(reflecting: collection).children.map(\.value)
}

private func lastEntry(_ collection: Any?) -> Any? {
    guard let collection = collection.flatMap(unwrapped) else { return nil }
    let children = Mirror(reflecting: collection).children
    return children.isEmpty ? nil : children.dropFirst(children.count - 1).first?.value
}

private func rawValue(_ identifier: Any?) -> String? {
    field(identifier, "rawValue") as? String
}

private func dictionaryPairs(_ dictionary: Any?) -> [(key: Any, value: Any)] {
    entries(dictionary).compactMap { pair in
        guard let key = field(pair, "key"), let value = field(pair, "value") else { return nil }
        return (key, value)
    }
}

private var applicationController: Any? {
    NSApp.delegate.flatMap { field($0, "controller") }
}

@_cdecl("DPDelegateShowsTabPage")
public func DPDelegateShowsTabPage(_ delegate: AnyObject) -> Bool {
    guard let controller = field(delegate, "navigationDelegate.delegate.delegate"),
        let owner = field(controller, "diagnosticOwner"), let type = field(controller, "webContentType") else { return false }
    return String(describing: owner) == "browserTab" && String(describing: type) == "primary"
}

@_cdecl("DPLoadedPaneStates")
public func DPLoadedPaneStates() -> NSDictionary {
    let states = NSMutableDictionary()
    for window in entries(field(applicationController, "windowCoordinationController.windowControllers")) {
        for (_, context) in dictionaryPairs(field(window, "windowBrowserContextControllers")) {
            var recorded: [String: String] = [:]
            for (pane, history) in dictionaryPairs(field(context, "lifecycleHistory.stateHistory")) {
                if let id = rawValue(pane), let last = lastEntry(field(history, "entries")),
                    let state = field(last, "value") {
                    recorded[id] = String(describing: state)
                }
            }
            for (pane, _) in dictionaryPairs(field(context, "contentTabBindingControllers")) {
                if let id = rawValue(pane) { states[id] = recorded[id] ?? "Alive" }
            }
        }
    }
    return states
}

@_cdecl("DPPanesOfRow")
public func DPPanesOfRow(_ row: NSView) -> NSArray {
    entries(field(row, "viewModel.stateSubject.currentValue.contentIDs")).compactMap(rawValue) as NSArray
}

@_cdecl("DPPanesOfDockItem")
public func DPPanesOfDockItem(_ item: NSView) -> NSArray {
    dictionaryPairs(field(item, "viewModel.delegate.contentControllers")).compactMap { rawValue($0.key) } as NSArray
}

/// Dia only takes the close button away from a pinned tab that is already closed.
@_cdecl("DPRowHasNoCloseButton")
public func DPRowHasNoCloseButton(_ row: NSView) -> Bool {
    field(row, "viewModel.delegate.suppressesCloseButton") as? Bool ?? false
}
