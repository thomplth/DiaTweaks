import Foundation

private func DPIDText(_ value: Any?, _ depth: Int = 0) -> String? {
    guard let value, depth < 5 else { return nil }
    if let text = value as? String { return DPIDNormalized(text) }
    if let text = value as? NSString { return DPIDNormalized(text as String) }
    if let uuid = value as? UUID { return uuid.uuidString.lowercased() }
    if let uuid = value as? NSUUID { return uuid.uuidString.lowercased() }
    if let number = value as? NSNumber { return number.stringValue }
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first else { return nil }
        return DPIDText(child.value, depth + 1)
    }
    for child in mirror.children where child.label == "rawValue" {
        if let key = DPIDText(child.value, depth + 1) { return key }
    }
    if mirror.children.count == 1, mirror.children.first?.label == nil {
        if let key = DPIDText(mirror.children.first?.value, depth + 1) { return key }
    }
    return DPIDNormalized(String(describing: value))
}

private func DPIDNormalized(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == "nil" || trimmed == "none" { return nil }
    let pattern = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
    if let range = trimmed.range(of: pattern, options: .regularExpression) { return String(trimmed[range]).lowercased() }
    return trimmed.count <= 120 ? trimmed : nil
}

private func DPSwiftValue(_ object: Any?, _ key: String) -> Any? {
    guard let object = object as? NSObject else { return nil }
    let sel = NSSelectorFromString("safeSwiftValueForKey:")
    guard object.responds(to: sel), let value = object.perform(sel, with: key) else { return nil }
    return value.takeUnretainedValue()
}

private func DPElements(_ value: Any?, _ depth: Int = 0) -> [Any] {
    guard let value, depth < 4 else { return [] }
    if let array = value as? NSArray { return array.map { $0 } }
    if let set = value as? NSSet { return set.allObjects }
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional { return DPElements(mirror.children.first?.value, depth + 1) }
    if mirror.displayStyle == .set || mirror.displayStyle == .collection { return mirror.children.map { $0.value } }
    if mirror.children.count == 1, mirror.children.first?.label == nil { return DPElements(mirror.children.first?.value, depth + 1) }
    for child in mirror.children {
        let nested = Mirror(reflecting: child.value)
        if nested.displayStyle == .set || nested.displayStyle == .collection { return nested.children.map { $0.value } }
    }
    return []
}

private func DPDictionaryValues(_ value: Any?, _ depth: Int = 0) -> [Any] {
    guard let value, depth < 4 else { return [] }
    if let dict = value as? NSDictionary { return dict.allValues }
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional { return DPDictionaryValues(mirror.children.first?.value, depth + 1) }
    if mirror.children.count == 1, mirror.children.first?.label == nil, mirror.displayStyle != .dictionary {
        return DPDictionaryValues(mirror.children.first?.value, depth + 1)
    }
    guard mirror.displayStyle == .dictionary else { return [] }
    return mirror.children.compactMap { child in
        let kids = Array(Mirror(reflecting: child.value).children)
        if let labeled = kids.first(where: { $0.label == "value" }) { return labeled.value }
        return kids.count >= 2 ? kids[1].value : nil
    }
}

@_cdecl("DPIDKey")
public func DPIDKey(_ value: AnyObject?) -> NSString? { DPIDText(value) as NSString? }

@_cdecl("DPSelectionIDKeys")
public func DPSelectionIDKeys(_ selection: AnyObject?) -> NSArray {
    guard let selection else { return [] }
    var keys: [String] = []
    func add(_ value: Any?) {
        guard let key = DPIDText(value), !keys.contains(key) else { return }
        keys.append(key)
    }
    let selected = DPElements(DPSwiftValue(selection, "allSelectedTabIDs"))
    if selected.isEmpty { add(DPSwiftValue(selection, "primarySelectedTabID")) }
    else { for value in selected { add(value) } }
    return keys as NSArray
}

@_cdecl("DPEachValue")
public func DPEachValue(_ collection: AnyObject?, _ visit: @escaping @convention(block) (AnyObject) -> Void) {
    let values = DPDictionaryValues(collection)
    for value in values.isEmpty ? DPElements(collection) : values { visit(value as AnyObject) }
}
