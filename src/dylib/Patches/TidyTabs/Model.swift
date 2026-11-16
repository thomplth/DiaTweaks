// One labelled field per tab and subject words, not numbers: the ~3B model mixes tabs up and repeats one number.
import Foundation
import XPC
#if canImport(FoundationModels)
import FoundationModels

// macOS 27 renames this samplingMode, but the macOS 26 SDK only has this spelling, so it's the one that builds on both.
@available(macOS 26, *)
private func DPTidyOptions() -> GenerationOptions { GenerationOptions(sampling: .greedy) }

@available(macOS 26, *)
private let DPTidyInstructions = """
    You sort a person's browser tabs by subject. Each tab is its title, then its web address. For each tab, in order:
    - about: 2 to 6 English words on what the page is for, naming the actual product, brand, place or topic from the \
    title or the address. Titles can be in any language.
    - subject: 1 or 2 lowercase English words naming the thing the tab is about. If an earlier tab is about the same \
    thing, copy its subject exactly. Otherwise write a new one.

    Rules:
    - The subject is the thing, not the activity: shopping for, reading about and comparing headphones are all \
    "headphones".
    - Different shops or apps for the same kind of thing share a subject: two perfume shops are "perfume", two \
    whiteboard apps are "whiteboard apps", a MacBook and an iPhone are "apple products".
    - Everything for one trip shares a subject: flights, hotels and guides for Lisbon are all "lisbon trip".
    - Different animals, foods or places are different subjects: cats and dogs are not the same.

    Example tabs:
    tab1: Nike Air Zoom Pegasus 41 – Men's Road Running Shoes (nike.com/t/air-zoom-pegasus-41)
    tab2: Wie lange kochen Eier? (chefkoch.de/magazin/eier-kochen)
    tab3: Flights Berlin to Lisbon – Skyscanner (skyscanner.net/routes/ber/lis)
    tab4: Wyprzedaż do -50% (sklepbiegacza.pl/buty-do-biegania)
    tab5: Best wet food for kittens (catster.com/guides/kitten-food)
    tab6: Hotels in Alfama, Lisbon – Booking.com (booking.com/district/pt/lisbon/alfama)
    tab7: dog training tips - Google Search (google.com/search)
    tab8: Royal Canin vs Purina kitten food (reddit.com/r/cats)
    tab9: Inbox (12) - Outlook (outlook.live.com/mail)

    Example answers:
    tab1 about: shopping for Nike running shoes; subject: running shoes
    tab2 about: how long to boil eggs; subject: eggs
    tab3 about: flights from Berlin to Lisbon; subject: lisbon trip
    tab4 about: running shoe sale; subject: running shoes
    tab5 about: choosing kitten food; subject: cat food
    tab6 about: hotels in Lisbon; subject: lisbon trip
    tab7 about: dog training tips; subject: dog training
    tab8 about: comparing kitten food brands; subject: cat food
    tab9 about: reading email; subject: email
    """

@available(macOS 26, *)
private func DPTidySubjects(_ lines: [String]) async throws -> [String] {
    let answer = DynamicGenerationSchema(name: "Tab", properties: [
        .init(name: "about", description: "2 to 6 English words naming the product, brand, place or topic", schema: .init(type: String.self)),
        .init(name: "subject", description: "1 or 2 lowercase words; copied exactly from an earlier tab about the same thing", schema: .init(type: String.self)),
    ])
    let fields = lines.indices.map {
        DynamicGenerationSchema.Property(name: "tab\($0 + 1)", description: lines[$0], schema: DynamicGenerationSchema(referenceTo: "Tab"))
    }
    let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "Tabs", properties: fields), dependencies: [answer])
    let prompt = lines.indices.map { "tab\($0 + 1): \(lines[$0])" }.joined(separator: "\n")
    let content = try await LanguageModelSession(instructions: DPTidyInstructions)
        .respond(to: prompt, schema: schema, options: DPTidyOptions()).content
    return lines.indices.map {
        let tab = try? content.value(GeneratedContent.self, forProperty: "tab\($0 + 1)")
        return DPTidyNormalize((try? tab?.value(String.self, forProperty: "subject")) ?? "")
    }
}

private func DPTidyMergeNarrower(_ subjects: [String]) -> [String] {
    let words = Dictionary(subjects.filter { !$0.isEmpty }.map { ($0, Set($0.split(separator: " "))) }, uniquingKeysWith: { a, _ in a })
    return subjects.map { subject in
        guard let own = words[subject] else { return subject }
        let broader = words.filter { $0.key != subject && $0.value.isStrictSubset(of: own) }.min { $0.value.count < $1.value.count }
        return broader?.key ?? subject
    }
}

private func DPTidyNormalize(_ subject: String) -> String {
    subject.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        .map { $0.count > 3 && $0.hasSuffix("s") && !$0.hasSuffix("ss") ? String($0.dropLast()) : $0 }
        .joined(separator: " ")
}

@available(macOS 26, *)
private func DPTidyUnavailable(_ availability: SystemLanguageModel.Availability) -> String? {
    switch availability {
    case .available: return nil
    case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings to use Tidy Tabs."
    case .unavailable(.deviceNotEligible): return "This Mac can't run Apple Intelligence."
    case .unavailable(.modelNotReady): return DPTidyIneligibleReason() ?? "Apple Intelligence is still downloading. Try again in a few minutes."
    default: return "Apple Intelligence isn't available."
    }
}

// modelNotReady also means macOS won't download the model; eligibility inputs are 3 when they pass and 2 when they fail.
private func DPTidyIneligibleReason() -> String? {
    typealias Domain = @convention(c) (UnsafePointer<CChar>) -> Int
    typealias Answer = @convention(c) (Int, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>,
                                       UnsafeMutablePointer<UnsafeMutableRawPointer?>, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    guard let domainSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "os_eligibility_domain_for_name"),
          let answerSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "os_eligibility_get_domain_answer") else { return nil }
    let domain = unsafeBitCast(domainSymbol, to: Domain.self)("OS_ELIGIBILITY_DOMAIN_GREYMATTER")
    var answer: UInt64 = 0, source: UInt64 = 0
    var statusPointer: UnsafeMutableRawPointer?, contextPointer: UnsafeMutableRawPointer?
    guard unsafeBitCast(answerSymbol, to: Answer.self)(domain, &answer, &source, &statusPointer, &contextPointer) == 0,
          let statusPointer else { return nil }
    // Both come back retained.
    let status = Unmanaged<AnyObject>.fromOpaque(statusPointer).takeRetainedValue() as! xpc_object_t
    let context = contextPointer.map { Unmanaged<AnyObject>.fromOpaque($0).takeRetainedValue() as! xpc_object_t }
    let fails = { (input: String) in xpc_dictionary_get_int64(status, "OS_ELIGIBILITY_INPUT_" + input) == 2 }
    if fails("DEVICE_CLASS") || fails("GENERATIVE_MODEL_SYSTEM") { return "This Mac can't run Apple Intelligence." }
    if fails("EXTERNAL_BOOT_DRIVE") { return "Apple Intelligence doesn't work while your Mac starts up from an external drive." }
    if fails("COUNTRY_LOCATION") || fails("COUNTRY_BILLING") { return "Apple Intelligence isn't available in your country or region yet." }
    if fails("DEVICE_REGION_CODE") { return "Apple Intelligence isn't available with your Mac's region. Change it in System Settings › General › Language & Region." }
    if fails("DEVICE_LANGUAGE") { return "Apple Intelligence doesn't support your Mac's language yet. Change it in System Settings › General › Language & Region." }
    if fails("SIRI_LANGUAGE") { return "Apple Intelligence doesn't support Siri's language yet. Change it in System Settings › Apple Intelligence & Siri." }
    if fails("DEVICE_AND_SIRI_LANGUAGE_MATCH") {
        let name = { (code: String) in Locale.current.localizedString(forIdentifier: code) ?? code }
        let devices = context.flatMap { xpc_dictionary_get_array($0, "OS_ELIGIBILITY_CONTEXT_ELIGIBLE_DEVICE_LANGUAGES") }
        guard let devices, xpc_array_get_count(devices) > 0, let mac = xpc_array_get_string(devices, 0) else {
            return "Apple Intelligence needs Siri set to the same language as your Mac. Change it in System Settings › Apple Intelligence & Siri."
        }
        return "Apple Intelligence needs Siri set to the same language as your Mac, \(name(String(cString: mac))). Change it in System Settings › Apple Intelligence & Siri."
    }
    return answer == 2 ? "Apple Intelligence isn't available with this Mac's settings." : nil
}
#endif

@_cdecl("DPTidyUnavailableReason")
public func DPTidyUnavailableReason() -> NSString? {
    #if canImport(FoundationModels)
    guard #available(macOS 26, *) else { return "Tidy Tabs needs macOS 26 or later." }
    return DPTidyUnavailable(SystemLanguageModel.default.availability) as NSString?
    #else
    return "This build has no FoundationModels."
    #endif
}

/// `done` gets groups of two or more 1-based tab numbers, or an error, on the main queue.
@_cdecl("DPTidyAskModel")
public func DPTidyAskModel(_ tabs: NSArray, _ done: @escaping @convention(block) (NSArray?, NSString?) -> Void) {
    func finish(_ groups: NSArray?, _ error: String?) {
        DispatchQueue.main.async { done(groups, error as NSString?) }
    }
    if let reason = DPTidyUnavailableReason() { return finish(nil, reason as String) }
    #if canImport(FoundationModels)
    guard #available(macOS 26, *) else { return }
    let lines = tabs.map { tab -> String in
        let tab = tab as? NSDictionary
        let title = String(((tab?["title"] as? String) ?? "").prefix(90))
        return "\(title) (\((tab?["address"] as? String) ?? ""))"
    }
    Task {
        do {
            let subjects = DPTidyMergeNarrower(try await DPTidySubjects(lines))
            var order: [String] = [], members: [String: [Int]] = [:]
            for (index, subject) in subjects.enumerated() where !subject.isEmpty {
                if members[subject] == nil { order.append(subject) }
                members[subject, default: []].append(index + 1)
            }
            let groups = order.compactMap { members[$0]!.count >= 2 ? members[$0]! as NSArray : nil }
            finish(groups as NSArray, nil)
        } catch {
            finish(nil, "The model couldn't group these tabs: \(error.localizedDescription)")
        }
    }
    #endif
}
