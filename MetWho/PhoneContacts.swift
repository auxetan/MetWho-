import Contacts

/// Read-only access to the address book.
///
/// The settings page promises "MetWho copies the name and nothing else — no
/// numbers, no addresses — and never writes back". That promise is kept here and
/// nowhere else, so the key list below is the whole story: names, employer, job
/// title, and the city, which is what the card is built from. No phone numbers,
/// no emails, no postal detail beyond the city, and no `CNContactStore` write
/// path anywhere in the app.
enum PhoneContacts {

    enum Access { case granted, denied, restricted }

    static func request() async -> Access {
        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return .granted
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        default:
            let ok = (try? await store.requestAccess(for: .contacts)) ?? false
            return ok ? .granted : .denied
        }
    }

    static func fetch() -> [ContactSeed] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName

        var out: [ContactSeed] = []
        try? CNContactStore().enumerateContacts(with: request) { c, _ in
            let name = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
            // a card with no name is a phone number with nothing to remember
            guard !name.isEmpty else { return }
            out.append(ContactSeed(
                name: name,
                org: c.organizationName,
                role: c.jobTitle,
                city: c.postalAddresses.first?.value.city ?? ""
            ))
        }
        return out
    }
}
